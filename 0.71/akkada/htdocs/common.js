
var detect = navigator.userAgent.toLowerCase();
var OS,browser,version,total,thestring;
var tD=document;

if (checkIt('konqueror'))
{
        browser = "Konqueror";
        OS = "Linux";
}
else if (checkIt('safari')) browser = "Safari"
else if (checkIt('omniweb')) browser = "OmniWeb"
else if (checkIt('opera')) browser = "Opera"
else if (checkIt('webtv')) browser = "WebTV";
else if (checkIt('icab')) browser = "iCab"
else if (checkIt('msie')) browser = "Internet Explorer"
else if (!checkIt('compatible'))
{
        browser = "Netscape Navigator"
        version = detect.charAt(8);
}
else browser = "An unknown browser";

if (!version) version = detect.charAt(place + thestring.length);

if (!OS)
{
        if (checkIt('linux')) OS = "Linux";
        else if (checkIt('x11')) OS = "Unix";
        else if (checkIt('mac')) OS = "Mac"
        else if (checkIt('win')) OS = "Windows"
        else OS = "an unknown operating system";
}

function checkIt(string)
{
        place = detect.indexOf(string) + 1;
        thestring = string;
        return place;
}


var ie5=tD.all&&tD.getElementById;
var ns6=tD.getElementById&&!tD.all;

var OBJ = 0;
var menuid = '';
var menu_visible = '';
var on_click=0;

function set_OBJ(o,mid,oc) {
  on_click = oc;
  if (menu_visible == '') {
    OBJ = o;
    menuid = mid;
    var flyout = tD.getElementById("ss");
  }
}

function clear_OBJ() {
  on_click = 0;
  if (menu_visible == '') {
    menuid = '';
  }
}

function set_CUR(o) {
    CUR = o;
}

function open_location(section, parameters, current, probe, section_params) {
  if (section == '') section = '0';
  if (parameters != '') parameters += OBJ;
  if (current == 'current') OBJ = CUR;
  root = root + OBJ+ ',' + section;
  if (section_params != null)
      root = root + ',' + section_params + parameters
  else
      root = root + parameters;
  close_flyout;
  location.href=root;
}

function open_flyout(event) {
  if (event == null)
     event = window.event;
  if (event.button != 2 && event.button != 0) return;
  if (menu_visible != '') close_flyout(event);
  if (menuid == '') return;
  if (menuid == 'no_popup') return false;

  var rightedge = ie5 ? tD.body.clientWidth - event.clientX : window.innerWidth - event.clientX;
  var bottomedge = ie5 ? tD.body.clientHeight - event.clientY : window.innerHeight - event.clientY;

  var flyout = ie5 ? eval( "tD.all.flyout_" + menuid) : tD.getElementById( "flyout_" + menuid);

  var f_w = flyout.offsetWidth;
  var f_h = flyout.offsetHeight;

  flyout.style.display = "none";
  if (rightedge < f_w)
    flyout.style.left = ie5 ? tD.body.scrollLeft + event.clientX-f_w : window.pageXOffset + event.clientX - f_w
  else
    flyout.style.left = ie5 ? tD.body.scrollLeft + event.clientX : window.pageXOffset + event.clientX

  if (bottomedge<f_h)
    flyout.style.top = ie5 ? tD.body.scrollTop + event.clientY - flyout.offsetHeight : window.pageYOffset + event.clientY - f_h
  else
    flyout.style.top = ie5 ? tD.body.scrollTop + event.clientY : window.pageYOffset + event.clientY
  flyout.style.display = "block";
  menu_visible = flyout;
  event.returnValue = false;
  return false;
}

function close_flyout(e) {
  if (menu_visible == '')
    return true;
  if (on_click == 1)
    return true;
  menu_visible.style.display = "none";
  menu_visible = '';
  clear_OBJ();
  return true;
}

tD.oncontextmenu = open_flyout;
tD.onclick = close_flyout;

function loadAkkada() {
  var x = null;
  if (tD.getElementById) {  // DOM3 = IE5, NS6
    x = tD.getElementById('progress1');
    if (x == null) return;
    x.style.display = 'none';
  } else {
    if (tD.layers) {  // Netscape 4
      if (tD.progress1 == null) return;
      tD.progress1.display = 'none';
    } else {  // IE 4
      if (tD.all.progress1 == null) return;
      tD.all.progress1.style.display = 'none';
    }
  }
}

function progress_update(p) {
  var x = tD.getElementById('progress1');
  if (x == null) return;
  x.style.width = p;
}

var timerID = null;
var REF = 0;

setCookie = function(cookieName, cookieValue, expires, path, domain, secure)
{   
    tD.cookie =
        escape(cookieName) + '=' + escape(cookieValue)
        + (expires ? '; expires=' + expires.toGMTString() : '')
        + (path ? '; path=' + path : '')
        + (domain ? '; domain=' + domain : '')
        + (secure ? '; secure' : '');
}

getCookie = function(cookieName)
{   
    var cookieValue = '';
    var posName = tD.cookie.indexOf(escape(cookieName) + '=');
    if (posName != -1)
    {   
        var posValue = posName + (escape(cookieName) + '=').length;
        var endPos = tD.cookie.indexOf(';', posValue);
        if (endPos != -1)
            cookieValue = unescape(tD.cookie.substring(posValue, endPos));
        else
            cookieValue = unescape(tD.cookie.substring(posValue));
    }
    return (cookieValue);
}

var page_refresh = getCookie('AKKADA_PAGE_REFRESH') || 'off';

getPageRefresh = function()
{   
    var a = getCookie('AKKADA_PREFRESH');
    if (a==null || a=='') return 600000;
    return a < 15000 ? 15000 : a;
}

setPageRefresh = function(res)
{   
    var expire=new Date();
    expire.setTime(expire.getTime()+630720000000);
    setCookie('AKKADA_PREFRESH', res, expire);
}

function button_ref()
{   
    var ref = tD.getElementById('button_ref').value;
    if (ref==null) ref = 600;
    ref = ref*1000;
    if (ref < 15000) ref = 15000;
    setPageRefresh(ref);
    if (REF)
    {   
        clearTimeout(timerID);
        timerID = setTimeout('page_reload()',ref);
        REF = ref/1000;
        tD.getElementById('button_ref').value = REF;
    }
}

function page_reload()
{   
    location.href = me;
}

function button_ref_load()
{   
    var a = getPageRefresh();
    tD.getElementById('button_ref').value = a/1000;
    timerID = setTimeout('page_reload()', a);
    REF = a/1000;
}

function refresh_update()
{   
    if (REF > 0)
    {   
        REF--;
        setTimeout('refresh_update()',1000);
        if (vmode < 10)
        {   
            var a = tD.getElementById('status_bar');
            var b = a.rows[0].cells.length;
            b = b - 3;
            a.rows[0].cells[b].style.display = "block";
            a.rows[0].cells[b].innerHTML = '<div style="width: 104px;"><nobr>refresh in ' + REF + ' sec</nobr></div>';
        }
        else
            window.status = 'refresh in ' + REF + ' sec';
    }
}

function refresh_stop()
{   
    REF = 0;
    if (timerID != null)
    {   
        clearTimeout(timerID);
    }
    var a = getPageRefresh();
    tD.getElementById('button_ref').value = a/1000;
    page_refresh = 'off';
    var expire=new Date();
    expire.setTime(expire.getTime()+630720000000);
    setCookie('AKKADA_PAGE_REFRESH', page_refresh, expire);

    if (vmode < 10)
    {   
        a = tD.getElementById('status_bar');
        var b = a.rows[0].cells.length;
        b = b - 3;
        a.rows[0].cells[b].style.display = "none";
        // a.rows[0].cells[b].innerHTML = '<div style="width: 104px;"><nobr>refresh stopped</nobr></div>';
    }
    else
        window.status = '';
}

function button_ref_enable_click()
{   
    if (REF > 0)
        refresh_stop()
    else
        refresh_start();
}

function refresh_start ()
{   
    button_ref_load();
    refresh_update();
    page_refresh = 'on';
    var expire=new Date();
    expire.setTime(expire.getTime()+630720000000);
    setCookie('AKKADA_PAGE_REFRESH', page_refresh, expire);
}

treeShowHide = function(state)
{   
    tD.getElementById('tree_menu').style.display = (state)?"block":"none";
    tD.getElementById('tree_closed').style.display = (state)?"none":"block";
    var expire=new Date();
    expire.setTime(expire.getTime()+630720000000);
    setCookie('AKKADA_TREE_MENU', state, expire);
    return;
}

function send_submit(e, fname)
{
    var key;

    if (window.event)
        key = window.event.keyCode;
    else
        key = e.which;

    if (key == 13)
        tD.forms[fname].submit() ;
}

function make_sure(message,url)
{
    if (confirm(message))
        location.href=url;
}

var cpf=false;
function cps(){cpf=true;}
function cp(){if(cpf){tD.execCommand("Copy");cpf=false;}}
tD.onselectionchange=cps;
tD.onmouseup=cp;

var oc = new Array();
oc[0] = new Array("/img/o.gif");
oc[1] = new Array("/img/c.gif");
function bc(i, n) {
  i.src=(tD.getElementById(n).style.display=="none")?oc[0]:oc[1];
  tD.getElementById(n).style.display=(tD.getElementById(n).style.display=="none")?"block":"none";
}

function nw(url,h,w) {
  var nw=window.open(url,"nw","height=" + h + ",width=" + w + ",resizable=yes,scrolling=auto,menu=no,toolbar=no");
}

