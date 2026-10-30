// Customer app / website translator: swaps English UI text for NG_CT[lang] entries (exact match, ' · ' parts, then _p patterns).
(function(){
  if(window.ngCust) return;
  var ORIG=new WeakMap(), LAST=new WeakMap(), PO=new WeakMap(), PL=new WeakMap();
  var lang='en', root=null, obs=null;
  function D(){ return (window.NG_CT||{})[lang]; }
  function pat(t,d){ var P=d._p||[]; for(var i=0;i<P.length;i++){ var m=t.match(P[i][0]); if(m) return P[i][1](m,d); } return null; }
  function one(t,d){ return d[t]!=null?d[t]:pat(t,d); }
  function tr(s){
    var d=D(); if(!d) return null; var t=s.trim(); if(!t||!/[A-Za-z]/.test(t)) return null;
    var r=one(t,d);
    if(r==null&&t.indexOf(' · ')>-1){ var ps=t.split(' · '), ch=false; var out=ps.map(function(p){ var x=one(p,d); if(x!=null){ch=true;return x;} return p; }); if(ch) r=out.join(' · '); }
    return r==null?null:s.replace(t,r);
  }
  function icon(n){ var p=n.parentElement; return p&&/Material/.test(p.style.fontFamily||''); }
  function doText(n){
    var v=n.nodeValue; if(LAST.get(n)===v) return; ORIG.set(n,v);
    var r=(lang==='en'||icon(n))?null:tr(v);
    if(r!=null&&r!==v){ LAST.set(n,r); n.nodeValue=r; } else LAST.set(n,v);
  }
  function doPh(el){
    var v=el.getAttribute('placeholder'); if(v==null||PL.get(el)===v) return; PO.set(el,v);
    var r=lang==='en'?null:tr(v);
    if(r!=null&&r!==v){ PL.set(el,r); el.setAttribute('placeholder',r); } else PL.set(el,v);
  }
  function walk(el,reset){
    var w=document.createTreeWalker(el,NodeFilter.SHOW_TEXT), n;
    while((n=w.nextNode())){ if(reset&&ORIG.has(n)&&LAST.get(n)===n.nodeValue){ n.nodeValue=ORIG.get(n); LAST.delete(n); } doText(n); }
    if(el.querySelectorAll) el.querySelectorAll('[placeholder]').forEach(function(e){ if(reset&&PO.has(e)&&PL.get(e)===e.getAttribute('placeholder')){ e.setAttribute('placeholder',PO.get(e)); PL.delete(e); } doPh(e); });
  }
  function onMut(ms){
    ms.forEach(function(m){
      if(m.type==='characterData') doText(m.target);
      else if(m.type==='attributes') doPh(m.target);
      else m.addedNodes.forEach(function(a){ if(a.nodeType===3) doText(a); else if(a.nodeType===1) walk(a,false); });
    });
  }
  window.ngCust={
    set:function(l,el){
      lang=l||'en'; root=el||document.body;
      document.documentElement.lang=lang;
      if(!obs){ obs=new MutationObserver(onMut); obs.observe(root,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['placeholder']}); }
      walk(root,true);
    },
    t:function(s){ var r=tr(s); return r==null?s:r; }
  };
})();
