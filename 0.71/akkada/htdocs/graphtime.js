var nimage = 6666;
var TP = '';

var start_pos = 6;

function open_graphtime(tperiod) {
  TP = tperiod;
  graph_reload();
}

function graph_reload(id) {
  var gid = OBJ.split(":");
  var url = gid.pop();
  var x = url.split(",");
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



