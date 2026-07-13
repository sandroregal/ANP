# ============================================================
# ROTINA DE ATUALIZAÇÃO - App ANP Royal FIC
# Baixa dados da ANP, filtra, converte e atualiza o app
# Executar entre os dias 20 e último dia de cada mês
# ============================================================

$ErrorActionPreference = "Stop"

# --- CONFIGURAÇÃO ---
$ANP_ZIP_URL  = "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/mdpg/liquidos.zip"
$ANP_PAGE_URL = "https://www.gov.br/anp/pt-br/centrais-de-conteudo/paineis-dinamicos-da-anp/paineis-dinamicos-do-abastecimento/painel-dinamico-do-mercado-brasileiro-de-combustiveis-liquidos"
$CSV_DIR      = "C:\Users\sandro.regal\OneDrive - ROYAL FIC DISTRIBUIDORA DE DERIVADOS DE PETROLEO\_4. BIBLIOTECA_PESQUISA\02_GERAL_RF\Inteligencia\ANP\Painel dinamico\painel-dinamico-dados-liquidos"
$REPO_DIR     = "C:\Users\sandro.regal\OneDrive - ROYAL FIC DISTRIBUIDORA DE DERIVADOS DE PETROLEO\_4. BIBLIOTECA_PESQUISA\03_SISTEMAS_DADOS\ANP"
$ANO_INICIO   = 2025
$CSV_FILTRADO = "$CSV_DIR\Liquidos_Vendas_Atual_v02.csv"

# --- FUNÇÕES ---

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg"
}

function Test-ANPAtualizada {
    Write-Log "Verificando se a ANP atualizou a base..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $resp = Invoke-WebRequest -Uri $ANP_PAGE_URL -UseBasicParsing -TimeoutSec 30
        $html = $resp.Content
        if ($html -match 'atualizado\s+em\s+(\d{1,2}/\d{1,2}/\d{4})') {
            $dataStr = $Matches[1]
            Write-Log "Data de atualização na página: $dataStr"
            $partes = $dataStr -split "/"
            $dataANP = [datetime]::new([int]$partes[2], [int]$partes[1], [int]$partes[0])
            $mesAtual = (Get-Date).Month
            $anoAtual = (Get-Date).Year
            if ($dataANP.Month -eq $mesAtual -and $dataANP.Year -eq $anoAtual) {
                Write-Log "Base atualizada neste mês. Prosseguindo..."
                return $true
            } else {
                Write-Log "Base ainda não atualizada neste mês (última: $dataStr). Abortando."
                return $false
            }
        }
        # Fallback: verificar pelo link do ZIP
        if ($html -match 'liquidos\.zip.*?atualiza.*?(\d{1,2}/\d{1,2}/\d{4})') {
            Write-Log "Data encontrada no link: $($Matches[1])"
            return $true
        }
        Write-Log "Não encontrou data de atualização na página. Tentando download direto..."
        return $true
    } catch {
        Write-Log "ERRO ao acessar página: $($_.Exception.Message)"
        return $false
    }
}

function Download-ANP {
    Write-Log "Baixando liquidos.zip da ANP..."
    $zipPath = "$CSV_DIR\liquidos.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ANP_ZIP_URL -OutFile $zipPath -UseBasicParsing -TimeoutSec 600
    $size = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Log "Download concluído: $size MB"

    Write-Log "Extraindo ZIP..."
    Expand-Archive -Path $zipPath -DestinationPath $CSV_DIR -Force
    Write-Log "Extração concluída."
    return "$CSV_DIR\Liquidos_Vendas_Atual.csv"
}

function Filtrar-CSV($csvOriginal) {
    Write-Log "Filtrando CSV: ano >= $ANO_INICIO..."
    $reader = New-Object System.IO.StreamReader($csvOriginal, [System.Text.Encoding]::Default)
    $writer = New-Object System.IO.StreamWriter($CSV_FILTRADO, $false, [System.Text.Encoding]::Default)

    $header = $reader.ReadLine()
    $writer.WriteLine($header)
    $count = 0

    while ($null -ne ($line = $reader.ReadLine())) {
        $ano = ($line -split ";")[0]
        if ([int]$ano -ge $ANO_INICIO) {
            $writer.WriteLine($line)
            $count++
        }
    }
    $reader.Close()
    $writer.Close()

    $size = [math]::Round((Get-Item $CSV_FILTRADO).Length / 1MB, 1)
    Write-Log "Filtrado: $count registros, $size MB"
}

function Converter-ParaRAW($csvPath) {
    Write-Log "Convertendo CSV para formato RAW do app..."

    $reader = New-Object System.IO.StreamReader($csvPath, [System.Text.Encoding]::Default)
    $null = $reader.ReadLine()

    $empresasSet = [System.Collections.Generic.SortedSet[string]]::new()
    $ufsSet = [System.Collections.Generic.SortedSet[string]]::new()
    $rows = [System.Collections.Generic.List[object]]::new()

    # Mapeamento de produtos ANP -> App
    $produtoMap = @{
        "ÓLEO DIESEL B S10 - COMUM" = "Diesel S10"
        "ÓLEO DIESEL B S10 - ADITIVADO" = "Diesel S10"
        "DIESEL B S10 PARA GERAÇÃO DE ENERGIA ELÉTRICA" = "Diesel S10"
        "ÓLEO DIESEL S10 B20 AUTORIZATIVO" = "Diesel S10"
        "ÓLEO DIESEL S10 B30 AUTORIZATIVO" = "Diesel S10"
        "ÓLEO DIESEL B S500 - COMUM" = "Diesel S500"
        "ÓLEO DIESEL B S500 - ADITIVADO" = "Diesel S500"
        "DIESEL B S500 PARA GERAÇÃO DE ENERGIA ELÉTRICA" = "Diesel S500"
        "GASOLINA C COMUM" = "Gasolina C"
        "GASOLINA C COMUM ADITIVADA" = "Gasolina C"
        "GASOLINA C PREMIUM" = "Gasolina C"
        "GASOLINA C PREMIUM ADITIVADA" = "Gasolina C"
        "ETANOL HIDRATADO COMUM" = "Etanol Hidratado"
        "ETANOL HIDRATADO ADITIVADO" = "Etanol Hidratado"
        "ÓLEO COMBUSTÍVEL A1" = "Oleo Combustivel"
        "ÓLEO COMBUSTÍVEL B1" = "Oleo Combustivel"
        "ÓLEO COMBUSTÍVEL MARÍTIMO" = "Oleo Combustivel"
        "ÓLEO COMBUSTÍVEL MARÍTIMO MISTURA (MF)" = "Oleo Combustivel"
        "OUTROS ÓLEOS COMBUSTÍVEIS" = "Oleo Combustivel"
        "DMA - MGO" = "Outros Diesel"
        "DMB - MDO" = "Outros Diesel"
        "ÓLEO DE XISTO" = "Outros Diesel"
        "OUTROS ÓLEOS DIESEL" = "Outros Diesel"
        "DIESEL B S1800 NÃO RODOVIÁRIO PARA GERAÇÃO DE ENERGIA ELÉTRICA" = "Outros Diesel"
    }

    # Mapeamento de segmentos ANP -> App
    $segmentoMap = @{
        "CONSUMIDOR FINAL" = "Consumidor Final"
        "POSTO DE COMBUSTÍVEIS - BANDEIRADO" = "Posto Bandeirado"
        "POSTO DE COMBUSTÍVEIS - BANDEIRA BRANCA" = "Posto Bandeira Branca"
        "TRR" = "TRR"
        "TRRNI" = "TRR"
    }

    $produtos = @("Diesel S10","Diesel S500","Etanol Hidratado","Gasolina C","Oleo Combustivel","Outros Diesel")
    $segmentos = @("Consumidor Final","Posto Bandeirado","Posto Bandeira Branca","TRR")
    $ufsValidas = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@("AC","AL","AM","AP","BA","CE","DF","ES","GO","MA","MG","MS","MT","PA","PB","PE","PI","PR","RJ","RN","RO","RR","RS","SC","SE","SP","TO")
    )

    while ($null -ne ($line = $reader.ReadLine())) {
        $f = $line -split ";"
        $ano = [int]$f[0]
        $mes = [int]$f[1]
        $empresa = $f[2]
        $descProd = $f[5]
        $uf = $f[9]
        $segmento = $f[10]
        $volStr = $f[11]

        $prodApp = $produtoMap[$descProd]
        $segApp = $segmentoMap[$segmento]

        if ($null -eq $prodApp -or $null -eq $segApp) { continue }
        if (-not $ufsValidas.Contains($uf)) { continue }

        $vol = [double]($volStr -replace ",", ".")
        if ($vol -le 0) { continue }

        $null = $empresasSet.Add($empresa)
        $null = $ufsSet.Add($uf)

        $rows.Add(@{
            ano = $ano; mes = $mes; empresa = $empresa
            produto = $prodApp; segmento = $segApp; uf = $uf; vol = $vol
        })
    }
    $reader.Close()

    Write-Log "Lidos $($rows.Count) registros válidos, $($empresasSet.Count) empresas, $($ufsSet.Count) UFs"

    # Criar índices
    $empresasList = [string[]]$empresasSet
    $ufsList = [string[]]$ufsSet
    $empIdx = @{}; for ($i = 0; $i -lt $empresasList.Count; $i++) { $empIdx[$empresasList[$i]] = $i }
    $prodIdx = @{}; for ($i = 0; $i -lt $produtos.Count; $i++) { $prodIdx[$produtos[$i]] = $i }
    $segIdx = @{}; for ($i = 0; $i -lt $segmentos.Count; $i++) { $segIdx[$segmentos[$i]] = $i }
    $ufIdx = @{}; for ($i = 0; $i -lt $ufsList.Count; $i++) { $ufIdx[$ufsList[$i]] = $i }

    # Agregar: chave = "ano,mes,empIdx,prodIdx,segIdx,ufIdx"
    Write-Log "Agregando dados..."
    $agg = @{}
    foreach ($r in $rows) {
        $key = "$($r.ano),$($r.mes),$($empIdx[$r.empresa]),$($prodIdx[$r.produto]),$($segIdx[$r.segmento]),$($ufIdx[$r.uf])"
        $agg[$key] = ($agg[$key] + 0) + $r.vol
    }
    Write-Log "Agregados: $($agg.Count) registros únicos"

    # Construir JSON
    Write-Log "Construindo JSON RAW..."
    $sb = [System.Text.StringBuilder]::new(3000000)
    $null = $sb.Append('const RAW = {"empresas":[')
    $null = $sb.Append(($empresasList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ',')
    $null = $sb.Append('],"produtos":[')
    $null = $sb.Append(($produtos | ForEach-Object { '"' + $_ + '"' }) -join ',')
    $null = $sb.Append('],"segmentos":[')
    $null = $sb.Append(($segmentos | ForEach-Object { '"' + $_ + '"' }) -join ',')
    $null = $sb.Append('],"ufs":[')
    $null = $sb.Append(($ufsList | ForEach-Object { '"' + $_ + '"' }) -join ',')
    $null = $sb.Append('],"dados":[')

    $first = $true
    foreach ($kv in ($agg.GetEnumerator() | Sort-Object Name)) {
        if (-not $first) { $null = $sb.Append(',') }
        $first = $false
        $vol = [math]::Round($kv.Value, 3)
        $null = $sb.Append("[$($kv.Name),$vol]")
    }
    $null = $sb.Append(']};')

    $rawLine = $sb.ToString()
    Write-Log "RAW gerado: $([math]::Round($rawLine.Length / 1MB, 2)) MB, $($agg.Count) rows de dados"

    return $rawLine
}

function Atualizar-IndexHTML($rawLine) {
    Write-Log "Atualizando index.html..."
    $indexPath = "$REPO_DIR\index.html"

    $content = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
    $pattern = 'const RAW = \{.*?\};'
    $content = [regex]::Replace($content, $pattern, $rawLine)
    [System.IO.File]::WriteAllText($indexPath, $content, [System.Text.Encoding]::UTF8)

    $size = [math]::Round((Get-Item $indexPath).Length / 1MB, 2)
    Write-Log "index.html atualizado: $size MB"
}

function Bump-SW {
    Write-Log "Atualizando versão do Service Worker..."
    $swPath = "$REPO_DIR\sw.js"
    $sw = Get-Content $swPath -Raw -Encoding UTF8
    $mesAno = Get-Date -Format "yyyy.MM"
    if ($sw -match "const CACHE_VERSION = '(v[^']+)'") {
        $oldVer = $Matches[1]
        $newVer = "v$mesAno"
        $sw = $sw -replace "const CACHE_VERSION = '[^']+'", "const CACHE_VERSION = '$newVer'"
        Set-Content $swPath $sw -Encoding UTF8 -NoNewline
        Write-Log "SW: $oldVer → $newVer"
    }
}

function Git-CommitPush {
    Write-Log "Fazendo commit e push..."
    Push-Location $REPO_DIR
    git add index.html sw.js
    $mesRef = (Get-Date).AddMonths(-1).ToString("MMM/yyyy")
    git commit -m "Atualiza dados ANP - ref. $mesRef"
    git push origin main
    Pop-Location
    Write-Log "Push concluído!"
}

# --- EXECUÇÃO PRINCIPAL ---

Write-Log "=== INÍCIO DA ATUALIZAÇÃO ANP ==="

$dia = (Get-Date).Day
$ultimoDia = [datetime]::DaysInMonth((Get-Date).Year, (Get-Date).Month)

if ($dia -lt 20 -or $dia -gt $ultimoDia) {
    Write-Log "Fora da janela de atualização (dia $dia, janela: 20 a $ultimoDia). Abortando."
    exit 0
}

if (-not (Test-ANPAtualizada)) {
    Write-Log "ANP não atualizou ainda. Tentando novamente nos próximos dias."
    exit 0
}

$csvOriginal = Download-ANP
Filtrar-CSV $csvOriginal
$rawLine = Converter-ParaRAW $CSV_FILTRADO
Atualizar-IndexHTML $rawLine
Bump-SW
Git-CommitPush

Write-Log "=== ATUALIZAÇÃO CONCLUÍDA COM SUCESSO ==="
