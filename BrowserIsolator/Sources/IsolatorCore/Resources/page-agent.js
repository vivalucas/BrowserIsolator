// Shared by both desktop products. Runs in a named isolated world, never changes navigator.
(() => {
  const KEY = '__isolator_page_agent_v1';
  if (globalThis[KEY]) return;
  const state = { document, snapshots: new Map(), watches: new Map(), sequence: 0 };
  const error = (code, message) => { throw new Error(`${code}: ${message}`); };
  const limit = (v, fallback, max) => Math.max(1, Math.min(Number(v) || fallback, max));
  const visible = el => { const s = getComputedStyle(el); return s.display !== 'none' && s.visibility !== 'hidden' && el.getClientRects().length > 0; };
  const disabled = el => el.matches(':disabled') || el.getAttribute('aria-disabled') === 'true';
  const editable = (el, value) => {
    if (el.readOnly || el.getAttribute('aria-readonly') === 'true') error('element_readonly','Element is read-only');
    if (!el.isContentEditable && !(el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && ['text','search','tel','url','email','password','number'].includes(el.type)))) error('invalid_element','Fill requires an editable text input, textarea, or contenteditable element');
    if (!el.isContentEditable && typeof value === 'string') { const probe=el.cloneNode(false);probe.value=value;if(probe.value!==value)error('invalid_value','The input type cannot retain this value'); }
  };
  const role = el => el.getAttribute('role') || ({ A:'link', BUTTON:'button', INPUT: /checkbox|radio/.test(el.type) ? el.type : el.type === 'submit' ? 'button' : 'textbox', TEXTAREA:'textbox', SELECT:'combobox', TABLE:'table', TR:'row', TH:'columnheader', TD:'cell', NAV:'navigation', MAIN:'main', FORM:'form', DIALOG:'dialog' }[el.tagName] || (/^H[1-6]$/.test(el.tagName) ? 'heading' : 'generic'));
  const name = el => {
    const labels = (el.getAttribute('aria-labelledby') || '').split(/\s+/).filter(Boolean).map(id => document.getElementById(id)?.textContent || '').join(' ');
    return (el.getAttribute('aria-label') || labels || Array.from(el.labels || []).map(l=>l.textContent).join(' ') || el.getAttribute('alt') || el.getAttribute('placeholder') || (['INPUT','TEXTAREA','SELECT'].includes(el.tagName) ? '' : el.textContent) || '').replace(/\s+/g,' ').trim();
  };
  const elements = () => { const out=[]; const walk=root=>{for(const el of root.querySelectorAll('*')){out.push(el);if(el.shadowRoot)walk(el.shadowRoot);}};walk(document);return out; };
  const meta = () => ({ url: location.href, title: document.title, readyState: document.readyState, capturedAt: new Date().toISOString(), viewport:{width:innerWidth,height:innerHeight}, scroll:{x:scrollX,y:scrollY} });
  const prune = () => { const now=Date.now();for(const [k,v] of state.snapshots)if(now-v.time>600000)state.snapshots.delete(k);while(state.snapshots.size>16)state.snapshots.delete(state.snapshots.keys().next().value); };
  function capture(p={}) {
    prune();const id=p.token || `s${++state.sequence}`;const refs=new Map(),nodes=[];const gaps=[];
    const maxNodes=limit(p.maxNodes,20000,100000),maxBytes=limit(p.maxCaptureBytes,8388608,33554432);let bytes=0,truncated=false;
    const visit=(node,parent,shadow=false)=>{
      if(truncated)return;
      if(nodes.length>=maxNodes || bytes>=maxBytes){truncated=true;return;}
      if(node.nodeType!==1 && node.nodeType!==3)return;
      const text=node.nodeType===3?(node.textContent||''):'';
      if(node.nodeType===3 && !text.trim())return;
      const ref=`n${nodes.length+1}`;refs.set(ref,node);
      let item;
      if(node.nodeType===3)item={ref,parent,type:'text',text,visible:node.parentElement?visible(node.parentElement):false};
      else {
        const r=node.getBoundingClientRect();const attrs=Object.fromEntries(Array.from(node.attributes,a=>[a.name,a.value]));
        const password=node.tagName==='INPUT' && node.type==='password';
        if(password && 'value' in attrs)attrs.value='[redacted]';
        item={ref,parent,type:'element',tag:node.tagName.toLowerCase(),role:role(node),name:(role(node)!=='generic'||node.hasAttribute('aria-label')||node.hasAttribute('aria-labelledby')?name(node):'').slice(0,500),attributes:attrs,visible:visible(node),disabled:disabled(node),checked:node.checked??null,selected:node.selected??null,expanded:node.getAttribute('aria-expanded'),value:password?'[redacted]':('value' in node?String(node.value):null),bounds:{x:r.x,y:r.y,width:r.width,height:r.height},shadow};
        if(node.tagName==='IFRAME')item.frame={src:node.getAttribute('src'),name:node.name};
      }
      bytes+=new TextEncoder().encode(JSON.stringify(item)).length;
      if(bytes>maxBytes){truncated=true;refs.delete(ref);return;}
      nodes.push(item);
      if(node.nodeType===1){
        if(node.shadowRoot)for(const c of node.shadowRoot.childNodes)visit(c,ref,true);
        for(const c of node.childNodes)visit(c,ref,shadow);
      }
    };
    visit(document.documentElement,null);if(truncated)gaps.push('capture_limit');
    state.snapshots.set(id,{time:Date.now(),document,nodes,refs,meta:meta(),complete:!truncated,gaps});prune();
    return {snapshot:id,...meta(),nodes,captureComplete:!truncated,gaps,totalNodes:nodes.length};
  }
  function stored(p){prune();const s=state.snapshots.get(p.snapshot);if(!s)error('snapshot_expired','Capture a fresh snapshot');return s;}
  function inspect(p){if(!p.ref){const el=select(p);const r=el.getBoundingClientRect();return {tag:el.tagName.toLowerCase(),role:role(el),name:name(el),attributes:Object.fromEntries(Array.from(el.attributes,a=>[a.name,a.value])),outerHTML:el.outerHTML,styles:Object.fromEntries(Array.from(getComputedStyle(el),k=>[k,getComputedStyle(el).getPropertyValue(k)])),bounds:{x:r.x,y:r.y,width:r.width,height:r.height},live:true,observedAt:new Date().toISOString()};}const s=stored(p),n=s.nodes.find(n=>n.ref===p.ref);if(!n)error('element_not_found','Unknown snapshot reference');const out={...n};if(p.live){const el=s.refs.get(p.ref);if(s.document!==document || !el?.isConnected)error('stale_reference','Element no longer exists');if(el.nodeType===1){out.outerHTML=el.outerHTML;out.styles=Object.fromEntries(Array.from(getComputedStyle(el),k=>[k,getComputedStyle(el).getPropertyValue(k)]));out.live=true;out.observedAt=new Date().toISOString();}}return out;}
  function select(p){
    let matches;
    if(p.ref){const s=stored(p);const n=s.refs.get(p.ref);if(s.document!==document || !n?.isConnected)error('stale_reference','Capture again before acting');matches=n.nodeType===1?[n]:[];}
    else if(p.selector){try{matches=elements().filter(el=>el.matches(p.selector));}catch{error('invalid_selector','Invalid CSS selector');}}
    else if(p.role || p.name){matches=elements().filter(el=>(!p.role||role(el)===p.role)&&(!p.name||name(el)===p.name));}
    else error('selector_required','Specify ref with snapshot, CSS selector, or role/name');
    if(matches.length!==1)error(matches.length?'ambiguous_element':'element_not_found',`Matched ${matches.length} elements`);
    return matches[0];
  }
  function resolve(p){const el=select(p);if(!visible(el))error('element_not_visible','Element is hidden');if(disabled(el))error('element_disabled','Element is disabled');const r=el.getBoundingClientRect();if(!r.width||!r.height)error('element_not_visible','Element has no layout');return {tag:el.tagName,role:role(el),name:name(el),bounds:{x:r.x,y:r.y,width:r.width,height:r.height},disabled:disabled(el),checked:!!el.checked,inputType:el.type};}
  function prepare(p){const el=select(p);resolve(p);if(p.editable)editable(el,p.value);el.scrollIntoView({block:'center',inline:'center',behavior:'instant'});const r=resolve(p).bounds;const x=r.x+r.width/2,y=r.y+r.height/2;let hit=document.elementFromPoint(x,y);while(hit?.shadowRoot){const inner=hit.shadowRoot.elementFromPoint(x,y);if(!inner||inner===hit)break;hit=inner;}if(hit!==el&&!el.contains(hit))error('element_obscured','Element is covered at its action point');if(p.focus)el.focus();return {x,y,...resolve(p)};}
  function action(p){const el=select(p);resolve(p);if(p.action==='select'){if(el.tagName!=='SELECT')error('invalid_element','Expected select');const option=Array.from(el.options).find(o=>o.value===p.value);if(!option)error('element_not_found','Option not found');el.value=p.value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));}else if(p.action==='clear'){editable(el,p.value);if(el.isContentEditable)el.textContent='';else{const proto=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(!setter)error('invalid_element','Element cannot accept text');setter.call(el,'');}el.dispatchEvent(new Event('input',{bubbles:true}));}else error('invalid_action','Unsupported page action');return {performed:true};}
  function verifyFill(p){const el=select(p);const value=el.isContentEditable?el.textContent:String(el.value);if(value!==p.value)error('input_not_applied','Input was dispatched but the page did not retain the requested value; inspect the page before retrying');return {valueApplied:true};}
  const relevant=(n,p)=>n.type==='text'?n.visible&&n.text.trim():n.visible&&(n.role!=='generic'||n.attributes.id||n.attributes['data-testid']);
  function read(p){const s=stored(p);let nodes=s.nodes;const view=p.view||'summary';if(p.root){const ids=new Set([p.root]);for(const n of nodes)if(ids.has(n.parent))ids.add(n.ref);nodes=nodes.filter(n=>ids.has(n.ref));}
    if(p.query){const q=String(p.query).toLowerCase();nodes=nodes.filter(n=>JSON.stringify(n).toLowerCase().includes(q));}
    if(view==='summary')nodes=nodes.filter(n=>relevant(n,p));else if(view==='text')nodes=nodes.filter(n=>n.type==='text'&&n.visible);
    const offset=Math.max(0,Number(p.offset)||0),count=limit(p.limit,40,500);const selected=nodes.slice(offset,offset+count).map(n=>view==='full'?n:{ref:n.ref,parent:n.parent,role:n.role,tag:n.tag,name:n.name,text:n.text,visible:n.visible,disabled:n.disabled,checked:n.checked,expanded:n.expanded,value:n.value});
    return {snapshot:p.snapshot,...s.meta,captureComplete:s.complete,gaps:s.gaps,total:nodes.length,offset,nodes:selected,nextOffset:offset+selected.length<nodes.length?offset+selected.length:null};
  }
  function condition(p){let el;try{el=select(p);}catch(e){if(String(e).includes('element_not_found'))return {matched:p.state==='absent',state:'absent'};throw e;}const found=visible(el);const matched=p.state==='absent'?false:p.state==='hidden'?!found:p.state==='enabled'?found&&!disabled(el):p.state==='checked'?el.checked===(p.checked??true):p.state==='value'?String(el.value)===String(p.value):p.state==='text'?el.textContent.includes(p.text||''):found;return {matched,state:found?'visible':'hidden'};}
  function watchStart(p){if(state.watches.size>=4)error('resource_limit','At most four watches per frame');const id=p.watch;const changes=[];let total=0,dropped=0;const observer=new MutationObserver(records=>{total+=records.length;for(const r of records){if(changes.length>=200){dropped++;continue;}changes.push({at:new Date().toISOString(),kind:r.type,tag:r.target.nodeName,attribute:r.attributeName,added:r.addedNodes.length,removed:r.removedNodes.length});}});const roots=[document.documentElement,...elements().filter(e=>e.shadowRoot).map(e=>e.shadowRoot)];for(const r of roots)observer.observe(r,{subtree:true,childList:true,attributes:true,characterData:true});const timer=setTimeout(()=>watchStop({watch:id}),limit(p.durationMs,60000,300000));state.watches.set(id,{observer,timer,changes,get total(){return total;},get dropped(){return dropped;},url:location.href});return {watch:id};}
  function watchPoll(p){const w=state.watches.get(p.watch);if(!w)return {events:[],expired:true,url:location.href};const events=w.changes.splice(0);return {events,totalEvents:w.total,dropped:w.dropped>0,url:location.href,urlChanged:w.url!==location.href};}
  function watchStop(p){const w=state.watches.get(p.watch);if(w){w.observer.disconnect();clearTimeout(w.timer);state.watches.delete(p.watch);}return {stopped:true};}
  globalThis[KEY]={forget:p=>({removed:state.snapshots.delete(p.snapshot)}),element:select,capture,read,inspect,resolve,prepare,action,verifyFill,condition,watchStart,watchPoll,watchStop,meta};
})();
