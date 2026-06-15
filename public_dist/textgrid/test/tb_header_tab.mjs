// ヘッダ編集中のTab/Shift+Tabで隣の列ヘッダの編集モードへ移動することを検証。
import { JSDOM } from 'jsdom';
import { initTableBuilder } from '/home/claude/textgrid/src/index.js';
const dom=new JSDOM('<!DOCTYPE html><body><div id="w" style="position:relative"></div></body>',{pretendToBeVisual:true});
const {window}=dom; global.window=window; global.document=window.document; global.Node=window.Node; global.Set=Set;
window.requestAnimationFrame=(cb)=>{cb();return 1;}; window.confirm=()=>true;
const wrapper=document.getElementById('w');
const api=initTableBuilder({wrapper,format:'markdown',t:(k,f)=>f,copy:()=>{},showEditor:()=>{}});
function assert(c,m){if(!c){console.error('  ✗',m);process.exitCode=1;}else{console.log('  ✓',m);}}

api.openForText('| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |','markdown',()=>({ok:true}),'k1',()=>{});

console.log('\n[1] ヘッダ編集 → Tab → 次の列のヘッダが編集モードになる');
// 列0のヘッダをダブルクリックして編集開始
const ch0 = wrapper.querySelector('th.tg-colhead[data-c="0"]');
ch0.dispatchEvent(new window.MouseEvent('dblclick', { bubbles: true, cancelable: true }));
let input = ch0.querySelector('input');
console.log('  列0編集開始 input:', !!input);
assert(!!input, '列0でinputが出現');

// 値を変更してTab
input.value = 'NewA';
const ev = new window.KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
input.dispatchEvent(ev);

// 列1で input が現れているはず
const ch1 = wrapper.querySelector('th.tg-colhead[data-c="1"]');
input = ch1.querySelector('input');
console.log('  Tab後 列1のinput:', !!input);
assert(!!input, '列1がTab後に編集モードに');
// 列0の値がコミットされている
console.log('  列0の値:', wrapper.querySelector('th.tg-colhead[data-c="0"] .tg-colhead-label')?.textContent || '(missing)');

console.log('\n[2] さらにTab → 列2が編集モード');
input.value = 'NewB';
input.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
const ch2 = wrapper.querySelector('th.tg-colhead[data-c="2"]');
input = ch2.querySelector('input');
assert(!!input, '列2が編集モードに');

console.log('\n[3] 最後の列でTab → 編集モードを抜ける');
input.value = 'NewC';
input.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
// 全ての列でinputが消えているはず
const anyInput = wrapper.querySelector('th.tg-colhead input');
assert(!anyInput, '最後の列でTabしたらinputが消える');

console.log('\n[4] Shift+Tab → 前の列のヘッダ編集モードへ');
// 列2のヘッダを再度編集開始
const ch2_again = wrapper.querySelector('th.tg-colhead[data-c="2"]');
ch2_again.dispatchEvent(new window.MouseEvent('dblclick', { bubbles: true, cancelable: true }));
input = ch2_again.querySelector('input');
assert(!!input, '列2で再編集開始');
input.value = 'C2';
// Shift+Tab
input.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Tab', shiftKey: true, bubbles: true, cancelable: true }));
// render()でDOMが再構築されているので取り直す
input = wrapper.querySelector('th.tg-colhead[data-c="1"] input');
assert(!!input, 'Shift+Tabで列1が編集モードに');

console.log('\n[5] 最初の列でShift+Tab → 編集モードを抜ける');
// 列0へ Shift+Tab で戻る
input.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Tab', shiftKey: true, bubbles: true, cancelable: true }));
input = wrapper.querySelector('th.tg-colhead[data-c="0"] input');
assert(!!input, '列0が編集モードに（Shift+Tab）');
// 最初の列でShift+Tab → 抜ける
input.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Tab', shiftKey: true, bubbles: true, cancelable: true }));
const noInput = wrapper.querySelector('th.tg-colhead input');
assert(!noInput, '最初の列でShift+Tabしたらinputが消える');

console.log('\n=== ヘッダTab/Shift+Tab検証完了 ===');
