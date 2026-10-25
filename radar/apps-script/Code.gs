/**
 * Radar de Atividades — Comercial SP (Royal FIC)
 * Backend do app: lê e grava a planilha "Agente de Rotina — Painel da Semana".
 *
 * Instalação (uma vez):
 * 1. Abra a planilha > Extensões > Apps Script. Apague o conteúdo e cole este arquivo.
 * 2. Em "Configurações do projeto" > "Propriedades do script", crie a propriedade TOKEN
 *    com uma senha longa só sua (ex.: 20+ caracteres). Ela protege o app.
 * 3. Implantar > Nova implantação > Tipo "App da Web".
 *    Executar como: Eu. Quem pode acessar: Qualquer pessoa.
 * 4. Autorize o acesso e copie a URL que termina em /exec. Ela vai no app, junto com o TOKEN.
 */

const SPREADSHEET_ID = '1LQAdkMAeJHpCo4zpO9v7bfi0as13eb-iZQ9exkCYNqk';
const SHEET_NAME = 'Untitled';
const COLS = ['id', 'frente', 'atividade', 'prioridade', 'dia', 'status', 'proximo', 'atualizacoes', 'radar', 'revisar'];
const EDITABLE = ['frente', 'atividade', 'prioridade', 'dia', 'status', 'proximo', 'radar', 'revisar'];

function doGet(e) {
  return handle_(function () {
    auth_(e.parameter.token);
    return { ok: true, items: list_() };
  });
}

function doPost(e) {
  return handle_(function () {
    const body = JSON.parse(e.postData.contents || '{}');
    auth_(body.token);
    const lock = LockService.getScriptLock();
    lock.waitLock(20000);
    try {
      if (body.action === 'update') return { ok: true, item: update_(body.id, body.fields || {}, body.nota) };
      if (body.action === 'add') return { ok: true, item: add_(body.fields || {}) };
      throw new Error('Ação desconhecida');
    } finally {
      lock.releaseLock();
    }
  });
}

function handle_(fn) {
  let out;
  try { out = fn(); } catch (err) { out = { ok: false, error: String(err.message || err) }; }
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}

function auth_(token) {
  const expected = PropertiesService.getScriptProperties().getProperty('TOKEN');
  if (!expected) throw new Error('TOKEN não configurado no Apps Script');
  if (!token || token !== expected) throw new Error('Acesso negado');
}

function sheet_() {
  return SpreadsheetApp.openById(SPREADSHEET_ID).getSheetByName(SHEET_NAME);
}

function rowToItem_(r, rowNumber) {
  const o = { row: rowNumber };
  COLS.forEach(function (k, i) {
    let v = r[i];
    if (k === 'radar') v = !(v === false || String(v).toUpperCase() === 'FALSE');
    else if (k === 'revisar') v = v === true || String(v).toUpperCase() === 'TRUE';
    else v = v == null ? '' : String(v);
    o[k] = v;
  });
  return o;
}

function list_() {
  const sh = sheet_();
  const last = sh.getLastRow();
  if (last < 2) return [];
  const vals = sh.getRange(2, 1, last - 1, COLS.length).getValues();
  const out = [];
  vals.forEach(function (r, i) { if (String(r[0]).trim()) out.push(rowToItem_(r, i + 2)); });
  return out;
}

function findRow_(id) {
  const sh = sheet_();
  const last = sh.getLastRow();
  const ids = sh.getRange(2, 1, Math.max(1, last - 1), 1).getValues();
  for (let i = 0; i < ids.length; i++) if (String(ids[i][0]).trim() === String(id).trim()) return i + 2;
  throw new Error('ID não encontrado: ' + id);
}

function stamp_(texto) {
  const d = Utilities.formatDate(new Date(), 'America/Sao_Paulo', 'dd/MM');
  return '[' + d + ' app] ' + texto;
}

function update_(id, fields, nota) {
  const sh = sheet_();
  const row = findRow_(id);
  Object.keys(fields).forEach(function (k) {
    if (EDITABLE.indexOf(k) < 0) return;
    let v = fields[k];
    if (k === 'radar' || k === 'revisar') v = !!v;
    else v = String(v == null ? '' : v).slice(0, 2000);
    sh.getRange(row, COLS.indexOf(k) + 1).setValue(v);
  });
  if (nota && String(nota).trim()) {
    const cell = sh.getRange(row, COLS.indexOf('atualizacoes') + 1);
    const cur = String(cell.getValue() || '');
    cell.setValue((cur ? cur + ' | ' : '') + stamp_(String(nota).trim().slice(0, 500)));
  }
  return rowToItem_(sh.getRange(row, 1, 1, COLS.length).getValues()[0], row);
}

function add_(fields) {
  const sh = sheet_();
  const items = list_();
  let id = String(fields.id || '').trim();
  if (!id) {
    const nums = items.map(function (it) { return parseInt(it.id, 10); }).filter(function (n) { return !isNaN(n) && /^\d+$/.test(String(n)); });
    id = String((nums.length ? Math.max.apply(null, nums) : 0) + 1);
  }
  if (items.some(function (it) { return it.id === id; })) throw new Error('ID já existe: ' + id);
  const row = [id];
  for (let i = 1; i < COLS.length; i++) {
    const k = COLS[i];
    if (k === 'radar') row.push(fields.radar === undefined ? true : !!fields.radar);
    else if (k === 'revisar') row.push(!!fields.revisar);
    else if (k === 'atualizacoes') row.push(stamp_('incluído pelo app'));
    else row.push(String(fields[k] == null ? '' : fields[k]).slice(0, 2000));
  }
  const r = sh.getLastRow() + 1;
  sh.getRange(r, 1, 1, COLS.length).setValues([row]);
  sh.getRange(r, 9, 1, 2).insertCheckboxes();
  return rowToItem_(row, r);
}
