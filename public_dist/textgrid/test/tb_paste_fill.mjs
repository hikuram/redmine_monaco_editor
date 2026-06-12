// 1×1コピー → 範囲ペースト = 範囲全部に同じ値を一括反映（Excel互換）
import { JSDOM } from 'jsdom';
import { initTableBuilder } from '/home/claude/rme/redmine_monaco_editor/public_dist/textgrid/src/index.js';
const dom=new JSDOM('<!DOCTYPE html><body><div id="w" style="position:relative"></div></body>',{pretendToBeVisual:true});
const {window}=dom; global.window=window; global.document=window.document; global.Node=window.Node; global.Set=Set;
window.requestAnimationFrame=(cb)=>{cb();return 1;}; window.confirm=()=>true;
class CB { constructor(){this.data={};} setData(t,v){this.data[t]=v;} getData(t){return this.data[t]||'';} }
const wrapper=document.getElementById('w');
const api=initTableBuilder({wrapper,format:'markdown',t:(k,f)=>f,copy:()=>{},showEditor:()=>{}});
function assert(c,m){if(!c){console.error('  ✗',m);process.exitCode=1;}else{console.log('  ✓',m);}}

console.log('\n[1] 1×1のテキストを6セル範囲に貼り付け');
// データ部 3行3列の表（| A | B | C | はヘッダ行）
api.openForText('| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |\n| 7 | 8 | 9 |','markdown',()=>({ok:true}),'k1',()=>{});

// セルを範囲選択する: (1,0)から(2,2)の6セル
// gridDivにフォーカス（textareaフォーカスを外す）
if (document.activeElement.tagName==='TEXTAREA') document.activeElement.blur();
const grid = wrapper.querySelector('.tg-grid');
grid.focus();

// 範囲選択を疑似: mousedown on (1,0) → mousemove to (2,2) → mouseup
const td10 = wrapper.querySelector('td[data-r="1"][data-c="0"]');
const td22 = wrapper.querySelector('td[data-r="2"][data-c="2"]');
console.log('  range-start td見つかった:', !!td10, '  end td:', !!td22);
const md = new window.MouseEvent('mousedown', { bubbles: true, cancelable: true });
td10.dispatchEvent(md);
const mm = new window.MouseEvent('mousemove', { bubbles: true, cancelable: true });
td22.dispatchEvent(mm);
const mu = new window.MouseEvent('mouseup', { bubbles: true, cancelable: true });
window.dispatchEvent ? window.dispatchEvent(mu) : document.dispatchEvent(mu);

// paste イベントを発火（クリップボードには「HELLO」だけ）
const cb = new CB();
cb.setData('text', 'HELLO');
const pe = new window.Event('paste', { bubbles: true, cancelable: true });
pe.clipboardData = cb;
const gridDiv = wrapper.querySelector('.tg-table').parentElement;
gridDiv.dispatchEvent(pe);

// 結果確認: データ部の(1,0)〜(2,2)が全部"HELLO"になっているはず
const checks = [
  [1,0,'HELLO'], [1,1,'HELLO'], [1,2,'HELLO'],
  [2,0,'HELLO'], [2,1,'HELLO'], [2,2,'HELLO'],
];
let allOk = true;
for (const [r, c, expected] of checks) {
  const sel = 'textarea.tg-cell-ta[data-r="' + r + '"][data-c="' + c + '"]';
  const ta = wrapper.querySelector(sel);
  const got = ta ? ta.value : '(no ta)';
  if (got !== expected) {
    console.log('  (' + r + ',' + c + '): "' + got + '" (期待 "' + expected + '")');
    allOk = false;
  }
}
assert(allOk, '範囲6セル全部に "HELLO" がコピーされた');

// 範囲外は変わっていないこと
const ta00 = wrapper.querySelector('textarea.tg-cell-ta[data-r="0"][data-c="0"]');
console.log('  (0,0)=', ta00 ? ta00.value : '(missing)');
assert(ta00 && ta00.value==='1', '範囲外のセル(0,0)は変わっていない');

console.log('\n=== 一括貼り付け検証完了 ===');
