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
    $lastRunFile = "$REPO_DIR\ultima_atualizacao.txt"
    $lastDate = ""
    if (Test-Path $lastRunFile) { $lastDate = (Get-Content $lastRunFile -Raw).Trim() }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $resp = Invoke-WebRequest -Uri $ANP_PAGE_URL -UseBasicParsing -TimeoutSec 30
        $html = $resp.Content
        if ($html -match 'atualizado\s+em\s+(\d{1,2}/\d{1,2}/\d{4})') {
            $dataStr = $Matches[1]
            Write-Log "Data de atualização na página: $dataStr"

            if ($dataStr -eq $lastDate) {
                Write-Log "Dados já atualizados com esta versão ($dataStr). Nada a fazer."
                return $false
            }

            Write-Log "Nova atualização disponível (anterior: $(if($lastDate){"$lastDate"}else{"nenhuma"}))"
            $script:novaDataANP = $dataStr
            return $true
        }
        if ($html -match 'liquidos\.zip.*?atualiza.*?(\d{1,2}/\d{1,2}/\d{4})') {
            $dataStr = $Matches[1]
            if ($dataStr -eq $lastDate) {
                Write-Log "Dados já atualizados com esta versão ($dataStr). Nada a fazer."
                return $false
            }
            Write-Log "Nova atualização encontrada: $dataStr"
            $script:novaDataANP = $dataStr
            return $true
        }
        Write-Log "Não encontrou data na página. Tentando download direto..."
        $script:novaDataANP = ""
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
    $empJson = ($empresasList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ','
    $prodJson = ($produtos | ForEach-Object { '"' + $_ + '"' }) -join ','
    $segJson = ($segmentos | ForEach-Object { '"' + $_ + '"' }) -join ','
    $ufJson = ($ufsList | ForEach-Object { '"' + $_ + '"' }) -join ','
    $headerPart = '"empresas":[' + $empJson + '],"produtos":[' + $prodJson + '],"segmentos":[' + $segJson + '],"ufs":[' + $ufJson + ']'

    # Agrupar dados por ano para possivel split
    $dadosPorAno = @{}
    foreach ($kv in ($agg.GetEnumerator() | Sort-Object Name)) {
        $ano = ($kv.Name -split ",")[0]
        $vol = [math]::Round($kv.Value, 3)
        $entry = "[$($kv.Name),$vol]"
        if (-not $dadosPorAno.ContainsKey($ano)) {
            $dadosPorAno[$ano] = [System.Collections.Generic.List[string]]::new()
        }
        $dadosPorAno[$ano].Add($entry)
    }

    $allEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($ano in ($dadosPorAno.Keys | Sort-Object)) {
        $allEntries.AddRange($dadosPorAno[$ano])
    }
    $dadosStr = $allEntries -join ','
    $fullRAW = 'const RAW = {' + $headerPart + ',"dados":[' + $dadosStr + ']};'

    $rawSizeMB = [math]::Round($fullRAW.Length / 1MB, 2)
    Write-Log "RAW gerado: $rawSizeMB MB, $($agg.Count) rows de dados"

    $SIZE_LIMIT = 30 * 1024 * 1024

    if ($fullRAW.Length -gt $SIZE_LIMIT) {
        Write-Log "RAW excede 30 MB. Dividindo por ano..."
        $anos = @($dadosPorAno.Keys | Sort-Object)
        foreach ($ano in $anos) {
            $yearEntries = $dadosPorAno[$ano] -join ','
            $yearContent = "var DATA_$ano = [$yearEntries];"
            $yearFile = "$REPO_DIR\data_$ano.js"
            [System.IO.File]::WriteAllText($yearFile, $yearContent, [System.Text.Encoding]::UTF8)
            $yearSize = [math]::Round((Get-Item $yearFile).Length / 1MB, 2)
            Write-Log "  data_$ano.js: $yearSize MB ($($dadosPorAno[$ano].Count) rows)"
        }
        $concatExpr = "DATA_$($anos[0])"
        for ($i = 1; $i -lt $anos.Count; $i++) { $concatExpr += ".concat(DATA_$($anos[$i]))" }
        $slimRAW = 'const RAW = {' + $headerPart + ',"dados":' + $concatExpr + '};'
        return @{ RAWLine = $slimRAW; Split = $true; Anos = $anos }
    }

    # Limpar arquivos split antigos se existem
    Get-ChildItem "$REPO_DIR\data_*.js" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Log "  Removido split antigo: $($_.Name)"
    }

    return @{ RAWLine = $fullRAW; Split = $false; Anos = @() }
}

function Atualizar-IndexHTML($result) {
    Write-Log "Atualizando index.html..."
    $indexPath = "$REPO_DIR\index.html"

    $content = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)

    # Remover tags de data files anteriores
    $content = [regex]::Replace($content, '<script src="data_\d{4}\.js"></script>\r?\n', '')

    # Substituir linha RAW
    $content = [regex]::Replace($content, 'const RAW = \{.*?\};', $result.RAWLine)

    # Se split, inserir tags de data files antes do <script> principal
    if ($result.Split) {
        $tags = ($result.Anos | ForEach-Object { "<script src=`"data_$_.js`"></script>" }) -join "`n"
        $content = [regex]::Replace($content, '(?=<script>\s+const RAW)', "$tags`n")
    }

    [System.IO.File]::WriteAllText($indexPath, $content, [System.Text.Encoding]::UTF8)

    $size = [math]::Round((Get-Item $indexPath).Length / 1MB, 2)
    $mode = if ($result.Split) { " (split: $($result.Anos -join ', '))" } else { "" }
    Write-Log "index.html atualizado: $size MB$mode"
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
        Write-Log "SW: $oldVer -> $newVer"
    }
}

function Git-CommitPush($splitInfo) {
    Write-Log "Fazendo commit e push..."
    Push-Location $REPO_DIR
    git add index.html sw.js
    if ($splitInfo.Split) {
        foreach ($ano in $splitInfo.Anos) { git add "data_$ano.js" }
    }
    $dataTracked = git ls-files "data_*.js"
    if ($dataTracked -and -not $splitInfo.Split) {
        foreach ($f in $dataTracked) { git rm $f }
    }
    $mesRef = (Get-Date).AddMonths(-1).ToString("MMM/yyyy")
    git commit -m "Atualiza dados ANP - ref. $mesRef"
    git push origin main
    Pop-Location
    Write-Log "Push concluído!"
}

# --- EXECUÇÃO PRINCIPAL ---

Write-Log "=== INÍCIO DA ATUALIZAÇÃO ANP ==="

$script:novaDataANP = ""

if (-not (Test-ANPAtualizada)) {
    Write-Log "Sem novos dados. Encerrando."
    exit 0
}

$csvOriginal = Download-ANP
Filtrar-CSV $csvOriginal
$result = Converter-ParaRAW $CSV_FILTRADO
Atualizar-IndexHTML $result
Bump-SW
Git-CommitPush $result

if ($script:novaDataANP) {
    $script:novaDataANP | Set-Content "$REPO_DIR\ultima_atualizacao.txt" -Encoding UTF8
    Write-Log "Data da atualização salva: $($script:novaDataANP)"
}

Write-Log "=== ATUALIZAÇÃO CONCLUÍDA COM SUCESSO ==="
