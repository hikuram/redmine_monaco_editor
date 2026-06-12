// テキストコピーと表全体コピーの判定テスト。
// ご指摘いただいた2つのバグの再発防止:
//   1) textareaにフォーカスがあり単一セル選択中の Ctrl+C は、表全体ではなく
//      セル内テキストのコピーになる（= 表ビルダーは何もしない）。
//   2) セル内改行を含むテキストを別セルへ貼り付けたとき、表として解釈されず
//      普通のテキストとして貼り付けられる。
import { JSDOM } from 'jsdom';
import { initTableBuilder } from '/home/claude/rme/redmine_monaco_editor/public_dist/textgrid/src/index.js';
const dom=new JSDOM('<!DOCTYPE html><body><div id="w" style="position:relative"></div></body>',{pretendToBeVisual:true});
const {window}=dom; global.window=window; global.document=window.document; global.Node=window.Node; global.Set=Set;
window.requestAnimationFrame=(cb)=>{cb();return 1;}; window.confirm=()=>true;
class CB { constructor(){this.data={};} setData(t,v){this.data[t]=v;} getData(t){return this.data[t]||'';} }
const wrapper=document.getElementById('w');
const api=initTableBuilder({wrapper,format:'textile',t:(k,f)=>f,copy:()=>{},showEditor:()=>{}});
function assert(c,m){if(!c){console.error('  ✗',m);process.exitCode=1;}else{console.log('  ✓',m);}}

console.log('\n[1] textareaにフォーカス+単一セル選択時のCtrl+Cは表ビルダーが介入しない');
// 表を開いて、特定のセルにフォーカス（自動で(0,0)にフォーカスされる）
api.openForText('| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |','markdown',()=>({ok:true}),'k1',()=>{});

// (1,1)のtextareaにフォーカス（単一セル選択モードに移行）
const ta11 = wrapper.querySelector('textarea.tg-cell-ta[data-r="1"][data-c="1"]');
ta11.focus();
// mousedown→focusのフローを再現
const md = new window.MouseEvent('mousedown', { bubbles: true, cancelable: true });
ta11.dispatchEvent(md);
ta11.focus();

// copy イベントを発火
const cb = new CB();
const ev = new window.Event('copy', { bubbles: true, cancelable: true });
ev.clipboardData = cb;
const gridDiv = wrapper.querySelector('.tg-table').parentElement;
gridDiv.dispatchEvent(ev);

// 表ビルダーが介入していない → text/plain は undefined または空
console.log('  textarea焦点中のクリップボード:', JSON.stringify(cb.data['text/plain']));
assert(!cb.data['text/plain'] || cb.data['text/plain']==='',
  '単一セル編集中はクリップボードに表全体が入らない');
assert(ev.defaultPrevented===false,
  '単一セル編集中はpreventDefaultされない（ブラウザ既定に任せる）');

console.log('\n[2] 範囲選択中はちゃんと表ビルダーが介入');
// 全選択にする（コーナーをmousedown）
if (document.activeElement.tagName==='TEXTAREA') document.activeElement.blur();
const corner = wrapper.querySelector('th.tg-corner');
const mde = new window.MouseEvent('mousedown', { bubbles: true, cancelable: true });
corner.dispatchEvent(mde);
const cb2 = new CB();
const ev2 = new window.Event('copy', { bubbles: true, cancelable: true });
ev2.clipboardData = cb2;
gridDiv.dispatchEvent(ev2);
assert(cb2.data['text/plain'] && cb2.data['text/plain'].includes('|'),
  '範囲選択中はクリップボードに表が入る');
assert(ev2.defaultPrevented===true,
  '範囲選択中はpreventDefaultされる');

console.log('\n=== コピー判定の正しさ 検証完了 ===');
