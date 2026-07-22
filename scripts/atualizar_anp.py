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

nova_data_anp = ""

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
    """Verifica se a ANP atualizou os dados desde a última execução."""
    global nova_data_anp
    nova_data_anp = ""

    last_date_file = os.path.join(REPO_DIR, "ultima_atualizacao.txt")
    last_date = ""
    if os.path.exists(last_date_file):
        with open(last_date_file, "r", encoding="utf-8") as f:
            last_date = f.read().strip()

    log("Verificando atualização na página da ANP...")
    try:
        req = urllib.request.Request(ANP_PAGE_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            html = resp.read().decode("utf-8", errors="replace")

        m = re.search(r'atualizado\s+em\s+(\d{1,2}/\d{1,2}/\d{4})', html, re.IGNORECASE)
        if not m:
            m = re.search(r'liquidos\.zip.*?atualiza.*?(\d{1,2}/\d{1,2}/\d{4})', html, re.IGNORECASE)
        if m:
            data_str = m.group(1)
            log(f"Data de atualização na página: {data_str}")

            if data_str == last_date:
                log(f"Dados já atualizados com esta versão ({data_str}). Nada a fazer.")
                return False

            anterior = last_date if last_date else "nenhuma"
            log(f"Nova atualização disponível (anterior: {anterior})")
            nova_data_anp = data_str
            return True

        log("Não encontrou data na página. Tentando download direto...")
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

    # Construir JSON agrupado por ano
    dados_por_ano = defaultdict(list)
    for key in sorted(agg.keys()):
        vol = round(agg[key], 3)
        entry = f"[{key[0]},{key[1]},{key[2]},{key[3]},{key[4]},{key[5]},{vol}]"
        dados_por_ano[key[0]].append(entry)

    emp_json = ",".join(json.dumps(e, ensure_ascii=False) for e in empresas_list)
    prod_json = ",".join(json.dumps(p) for p in PRODUTOS_APP)
    seg_json = ",".join(json.dumps(s) for s in SEGMENTOS_APP)
    uf_json = ",".join(json.dumps(u) for u in UFS_VALIDAS)
    header_part = f'"empresas":[{emp_json}],"produtos":[{prod_json}],"segmentos":[{seg_json}],"ufs":[{uf_json}]'

    all_dados = []
    for ano in sorted(dados_por_ano.keys()):
        all_dados.extend(dados_por_ano[ano])
    dados_json = ",".join(all_dados)

    full_raw = f'const RAW = {{{header_part},"dados":[{dados_json}]}};'

    raw_size_mb = len(full_raw.encode("utf-8")) / 1024 / 1024
    log(f"RAW gerado: {raw_size_mb:.2f} MB, {len(agg)} rows de dados")

    SIZE_LIMIT_MB = 30

    if raw_size_mb > SIZE_LIMIT_MB:
        log(f"RAW excede {SIZE_LIMIT_MB} MB. Dividindo por ano...")
        anos = sorted(dados_por_ano.keys())
        for ano in anos:
            year_entries = ",".join(dados_por_ano[ano])
            year_content = f"var DATA_{ano} = [{year_entries}];"
            year_path = os.path.join(REPO_DIR, f"data_{ano}.js")
            with open(year_path, "w", encoding="utf-8") as f:
                f.write(year_content)
            year_size = os.path.getsize(year_path) / 1024 / 1024
            log(f"  data_{ano}.js: {year_size:.2f} MB ({len(dados_por_ano[ano])} rows)")

        concat_expr = f"DATA_{anos[0]}"
        for ano in anos[1:]:
            concat_expr += f".concat(DATA_{ano})"
        slim_raw = f'const RAW = {{{header_part},"dados":{concat_expr}}};'
        return {"raw_line": slim_raw, "split": True, "anos": anos}

    # Limpar arquivos split antigos
    import glob
    for f in glob.glob(os.path.join(REPO_DIR, "data_*.js")):
        os.remove(f)
        log(f"  Removido split antigo: {os.path.basename(f)}")

    return {"raw_line": full_raw, "split": False, "anos": []}


def update_index(result):
    """Substitui o RAW no index.html, com suporte a split por ano."""
    log("Atualizando index.html...")
    with open(INDEX_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Remover tags de data files anteriores
    content = re.sub(r'<script src="data_\d{4}\.js"></script>\n?', '', content)

    # Substituir linha RAW
    content = re.sub(r'const RAW = \{.*?\};', result["raw_line"], content, count=1)

    # Se split, inserir tags antes do <script> principal
    if result["split"]:
        tags = "\n".join(f'<script src="data_{ano}.js"></script>' for ano in result["anos"])
        content = re.sub(r'(?=<script>\s+const RAW)', tags + "\n", content)

    with open(INDEX_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    size = os.path.getsize(INDEX_PATH) / 1024 / 1024
    mode = f" (split: {', '.join(str(a) for a in result['anos'])})" if result["split"] else ""
    log(f"index.html atualizado: {size:.2f} MB{mode}")


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


def save_last_date():
    """Salva a data da atualização para evitar reprocessamento."""
    global nova_data_anp
    if nova_data_anp:
        last_date_file = os.path.join(REPO_DIR, "ultima_atualizacao.txt")
        with open(last_date_file, "w", encoding="utf-8") as f:
            f.write(nova_data_anp)
        log(f"Data da atualização salva: {nova_data_anp}")


def main():
    log("=== INÍCIO DA ATUALIZAÇÃO ANP ===")

    if not check_anp_updated():
        log("Sem novos dados. Encerrando.")
        sys.exit(0)

    csv_text = download_and_extract()
    result = parse_and_convert(csv_text)
    update_index(result)
    bump_sw()
    save_last_date()

    log("=== ATUALIZAÇÃO CONCLUÍDA ===")


if __name__ == "__main__":
    main()
