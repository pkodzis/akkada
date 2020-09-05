var nimage = 6666;
var TP = '';
var Wi = null;
var He = null;

var start_pos = 6;

function open_graphtime(tperiod) {
  TP = tperiod;
  graph_reload();
}

function zoom(w, h, inout) {
  if (Wi == null) Wi = w;
  if (He == null) He = h;
  if (inout == true) {
    Wi = Wi+Wi*0.4;
    He = He+He*0.4;
  } else {
    Wi = Wi-Wi*0.4;
    He = He-He*0.4;
  }
  if (Wi < 10) Wi = 10;
  if (He < 10) He = 10;
  graph_reload();
}

function graph_reload(id) {
  var gid;
  if (id == null) {
      gid = OBJ.split(":");
  } else {
      gid = id.split(":");
  }
  var url = gid.pop();
  var x = url.split(",");

  if (Wi != null) {
      x[15] = Wi;
  }
  if (He!= null) {
      x[16] = He;
  }

  x[start_pos] = gid[0];
  x[start_pos+1] = TP;
  x[x.length-1] = nimage;
  url = x.join(",");
  nimage = nimage + 1;
  close_flyout;
  gid = gid.join(":");
  x = document.getElementById(gid);
  var im = new Image();
  im.src = url;
  x.src = im.src;
}

function cpi(){
  var g = OBJ.split(":");
  var im = g[0] + ":" + g[1] + ":" + g[2];
  im = document.getElementById(im);
  im.contentEditable = 'true';
  if (document.body.createControlRange) {
     g = document.body.createControlRange();
     g.addElement(im);
     g.execCommand('Copy');
  }
  im.contentEditable = 'false';
}



