"""
Atualiza dados ANP no index.html do app Royal FIC.
Baixa CSV da ANP, filtra jan/2025+, converte para RAW, atualiza index.html e sw.js.
Roda localmente ou via GitHub Actions.
"""

import csv
import io
import json
import os
import re
import sys
import urllib.request
import zipfile
from collections import defaultdict
from datetime import date

ANP_ZIP_URL = "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/mdpg/liquidos.zip"
ANP_PAGE_URL = "https://www.gov.br/anp/pt-br/centrais-de-conteudo/paineis-dinamicos-da-anp/paineis-dinamicos-do-abastecimento/painel-dinamico-do-mercado-brasileiro-de-combustiveis-liquidos"
ANO_INICIO = 2025
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(SCRIPT_DIR)
INDEX_PATH = os.path.join(REPO_DIR, "index.html")
SW_PATH = os.path.join(REPO_DIR, "sw.js")

PRODUTOS_APP = ["Diesel S10", "Diesel S500", "Etanol Hidratado", "Gasolina C", "Oleo Combustivel", "Outros Diesel"]
SEGMENTOS_APP = ["Consumidor Final", "Posto Bandeirado", "Posto Bandeira Branca", "TRR"]
UFS_VALIDAS = sorted(["AC","AL","AM","AP","BA","CE","DF","ES","GO","MA","MG","MS","MT","PA","PB","PE","PI","PR","RJ","RN","RO","RR","RS","SC","SE","SP","TO"])

PRODUTO_MAP = {
    "ÓLEO DIESEL B S10 - COMUM": "Diesel S10",
    "ÓLEO DIESEL B S10 - ADITIVADO": "Diesel S10",
    "DIESEL B S10 PARA GERAÇÃO DE ENERGIA ELÉTRICA": "Diesel S10",
    "ÓLEO DIESEL S10 B20 AUTORIZATIVO": "Diesel S10",
    "ÓLEO DIESEL S10 B30 AUTORIZATIVO": "Diesel S10",
    "ÓLEO DIESEL B S500 - COMUM": "Diesel S500",
    "ÓLEO DIESEL B S500 - ADITIVADO": "Diesel S500",
    "DIESEL B S500 PARA GERAÇÃO DE ENERGIA ELÉTRICA": "Diesel S500",
    "GASOLINA C COMUM": "Gasolina C",
    "GASOLINA C COMUM ADITIVADA": "Gasolina C",
    "GASOLINA C PREMIUM": "Gasolina C",
    "GASOLINA C PREMIUM ADITIVADA": "Gasolina C",
    "ETANOL HIDRATADO COMUM": "Etanol Hidratado",
    "ETANOL HIDRATADO ADITIVADO": "Etanol Hidratado",
    "ÓLEO COMBUSTÍVEL A1": "Oleo Combustivel",
    "ÓLEO COMBUSTÍVEL B1": "Oleo Combustivel",
    "ÓLEO COMBUSTÍVEL MARÍTIMO": "Oleo Combustivel",
    "ÓLEO COMBUSTÍVEL MARÍTIMO MISTURA (MF)": "Oleo Combustivel",
    "OUTROS ÓLEOS COMBUSTÍVEIS": "Oleo Combustivel",
    "DMA - MGO": "Outros Diesel",
    "DMB - MDO": "Outros Diesel",
    "ÓLEO DE XISTO": "Outros Diesel",
    "OUTROS ÓLEOS DIESEL": "Outros Diesel",
    "DIESEL B S1800 NÃO RODOVIÁRIO PARA GERAÇÃO DE ENERGIA ELÉTRICA": "Outros Diesel",
}

SEGMENTO_MAP = {
    "CONSUMIDOR FINAL": "Consumidor Final",
    "POSTO DE COMBUSTÍVEIS - BANDEIRADO": "Posto Bandeirado",
    "POSTO DE COMBUSTÍVEIS - BANDEIRA BRANCA": "Posto Bandeira Branca",
    "TRR": "TRR",
    "TRRNI": "TRR",
}


def log(msg):
    print(f"[ANP] {msg}", flush=True)


def check_anp_updated():
    """Verifica se a ANP atualizou os dados neste mês."""
    log("Verificando atualização na página da ANP...")
    try:
        req = urllib.request.Request(ANP_PAGE_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            html = resp.read().decode("utf-8", errors="replace")

        m = re.search(r'liquidos\.zip.*?atualiza.*?(\d{1,2}/\d{1,2}/\d{4})', html, re.IGNORECASE)
        if not m:
            m = re.search(r'[Aa]tualizado\s+em\s+(\d{1,2}/\d{1,2}/\d{4})', html)
        if m:
            data_str = m.group(1)
            partes = data_str.split("/")
            dia, mes, ano = int(partes[0]), int(partes[1]), int(partes[2])
            hoje = date.today()
            log(f"Data de atualização na página: {data_str}")
            if ano == hoje.year and mes == hoje.month:
                log("Base atualizada neste mês!")
                return True
            elif ano == hoje.year and mes == hoje.month - 1 and hoje.day <= 5:
                log("Base do mês anterior, mas estamos no início do mês. OK.")
                return True
            else:
                log(f"Base não atualizada neste mês (última: {data_str}).")
                return False
        log("Não encontrou data. Tentando download direto...")
        return True
    except Exception as e:
        log(f"Erro ao verificar página: {e}. Tentando download direto...")
        return True


def download_and_extract():
    """Baixa o ZIP da ANP e retorna o CSV de vendas como string."""
    log(f"Baixando {ANP_ZIP_URL}...")
    req = urllib.request.Request(ANP_ZIP_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        zip_data = resp.read()
    log(f"Download: {len(zip_data) / 1024 / 1024:.1f} MB")

    with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
        for name in zf.namelist():
            log(f"  ZIP contém: {name}")
        csv_data = zf.read("Liquidos_Vendas_Atual.csv")

    log(f"CSV extraído: {len(csv_data) / 1024 / 1024:.1f} MB")
    return csv_data.decode("latin-1")


def parse_and_convert(csv_text):
    """Converte CSV da ANP para o formato RAW do app."""
    log("Convertendo CSV para RAW...")

    empresas_set = set()
    ufs_set = set(UFS_VALIDAS)
    prod_idx = {p: i for i, p in enumerate(PRODUTOS_APP)}
    seg_idx = {s: i for i, s in enumerate(SEGMENTOS_APP)}

    rows = []
    reader = csv.reader(io.StringIO(csv_text), delimiter=";")
    header = next(reader)
    skipped = 0

    for row in reader:
        if len(row) < 12:
            continue
        ano = int(row[0])
        if ano < ANO_INICIO:
            continue

        mes = int(row[1])
        empresa = row[2]
        desc_prod = row[5]
        uf = row[9]
        segmento = row[10]
        vol_str = row[11]

        prod_app = PRODUTO_MAP.get(desc_prod)
        seg_app = SEGMENTO_MAP.get(segmento)

        if prod_app is None or seg_app is None:
            skipped += 1
            continue
        if uf not in ufs_set:
            skipped += 1
            continue

        vol = float(vol_str.replace(",", "."))
        if vol <= 0:
            skipped += 1
            continue

        empresas_set.add(empresa)
        rows.append((ano, mes, empresa, prod_app, seg_app, uf, vol))

    empresas_list = sorted(empresas_set)
    emp_idx = {e: i for i, e in enumerate(empresas_list)}
    uf_idx = {u: i for i, u in enumerate(UFS_VALIDAS)}

    log(f"Registros válidos: {len(rows)}, ignorados: {skipped}")
    log(f"Empresas: {len(empresas_list)}, UFs: {len(UFS_VALIDAS)}")

    # Agregar
    agg = defaultdict(float)
    for ano, mes, empresa, prod, seg, uf, vol in rows:
        key = (ano, mes, emp_idx[empresa], prod_idx[prod], seg_idx[seg], uf_idx[uf])
        agg[key] += vol

    log(f"Rows agregados: {len(agg)}")

    # Último período
    max_periodo = max((k[0], k[1]) for k in agg.keys())
    log(f"Último período: {max_periodo[1]:02d}/{max_periodo[0]}")

    # Construir JSON
    dados = []
    for key in sorted(agg.keys()):
        vol = round(agg[key], 3)
        dados.append(f"[{key[0]},{key[1]},{key[2]},{key[3]},{key[4]},{key[5]},{vol}]")

    emp_json = ",".join(json.dumps(e, ensure_ascii=False) for e in empresas_list)
    prod_json = ",".join(json.dumps(p) for p in PRODUTOS_APP)
    seg_json = ",".join(json.dumps(s) for s in SEGMENTOS_APP)
    uf_json = ",".join(json.dumps(u) for u in UFS_VALIDAS)
    dados_json = ",".join(dados)

    raw_line = f'const RAW = {{"empresas":[{emp_json}],"produtos":[{prod_json}],"segmentos":[{seg_json}],"ufs":[{uf_json}],"dados":[{dados_json}]}};'

    log(f"RAW gerado: {len(raw_line) / 1024 / 1024:.2f} MB, {len(agg)} rows de dados")
    return raw_line


def update_index(raw_line):
    """Substitui o RAW no index.html."""
    log("Atualizando index.html...")
    with open(INDEX_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    old_size = len(content)
    content = re.sub(r'const RAW = \{.*?\};', raw_line, content, count=1)
    new_size = len(content)

    with open(INDEX_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    log(f"index.html: {old_size / 1024 / 1024:.2f} MB → {new_size / 1024 / 1024:.2f} MB")


def bump_sw():
    """Atualiza a versão do cache no Service Worker."""
    log("Atualizando sw.js...")
    with open(SW_PATH, "r", encoding="utf-8") as f:
        sw = f.read()

    new_ver = date.today().strftime("v%Y.%m")
    sw_new = re.sub(r"const CACHE_VERSION = '[^']+'", f"const CACHE_VERSION = '{new_ver}'", sw)

    with open(SW_PATH, "w", encoding="utf-8") as f:
        f.write(sw_new)

    log(f"SW versão → {new_ver}")


def main():
    log("=== INÍCIO DA ATUALIZAÇÃO ANP ===")

    if not check_anp_updated():
        log("ANP não atualizou ainda. Abortando.")
        sys.exit(0)

    csv_text = download_and_extract()
    raw_line = parse_and_convert(csv_text)
    update_index(raw_line)
    bump_sw()

    log("=== ATUALIZAÇÃO CONCLUÍDA ===")


if __name__ == "__main__":
    main()
