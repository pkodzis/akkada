function Node(id, pid, name, url, title, target, isopen, img, status, ip, probe, no_status, no_popup, no_status_2)
{
	this.id = id;
	this.pid = pid;
	this.name = name;
	this.url = url;
	this.title = title;
	this.target = target;
	this.img = img;
	this.status = status;
	this.ip = ip;
	this.probe = probe;
	this.no_status = no_status;
	this.no_popup = no_popup;
	this.no_status_2 = no_status_2;

	this._io = isopen || false;
	this._ls = false;
	this._hc = false;
	this._is = false;
}

function dTree(objName)
{
	this.arrNodes = [];
	this.arrRecursed = [];
	this.arrIcons = [];
	this.rootNode = -1;
	this.strOutput = '';
	this.selectedNode = null;
	this.selectedInstance = null;

	this.instanceName = objName;
	this.imgFolder = '/img/';
	this.target = null;
	this.hasLines = true;
	this.clickSelect = true;
	this.folderLinks = true;
	this.useCookies = true;

	this.add = function(id, pid, name, url, title, target, isopen, img, status, ip, probe, no_status, no_popup, no_status_2)
	{
		this.arrNodes[this.arrNodes.length] = new Node(id, pid, name, url, title, target, isopen, img, status, ip, probe, no_status, no_popup, no_status_2);
	}

	this.draw = function(xselect)
	{
		if (document.getElementById)
		{
			this.preloadIcons();
			if (this.useCookies) this.selectedNode = this.getSelected(xselect);
			this.addNode(this.rootNode);
			document.writeln('<nobr>');
			document.writeln(this.strOutput);
			document.writeln('</nobr>');
		}
		else
		{
			document.writeln('Browser not supported.');
		}
	}

        this.futils = function(state)
        {
                var theDoc=document, theAll=(theDoc.all)?theDoc.all:null;
                if (theAll==null) return;
                theAll["futils"].setAttribute('src', state);
        }

        this.ipShowHide = function()
        {
		this.hide_ip = this.hide_ip == 'true' ? 'false' : 'true';
                var expire=new Date();
                expire.setTime(expire.getTime()+630720000000);
		this.setCookie('AKKADA_HIDE_IP', this.hide_ip, expire);
                window.location.reload();
        }

        this.treeSort = function()
        {
		this.tree_sort = this.tree_sort == 'true' ? 'false' : 'true';
                var expire=new Date();
                expire.setTime(expire.getTime()+630720000000);
		this.setCookie('AKKADA_TREE_SORT', this.tree_sort, expire);
                window.location.reload();
        }

        this.statusShowHide = function()
        {
		this.hide_status = this.hide_status == 'true' ? 'false' : 'true';
                var expire=new Date();
                expire.setTime(expire.getTime()+630720000000);
		this.setCookie('AKKADA_HIDE_STATUS', this.hide_status, expire);
                window.location.reload();
        }

	this.openAll = function()
	{
		this.oAll(true);
	}

	this.closeAll = function()
	{
		this.oAll(false);
	}

	this.preloadIcons = function()
	{
		if (this.hasLines)
		{
			this.arrIcons[0] = new Image();
			this.arrIcons[0].src = this.imgFolder + 'plus.gif';
			this.arrIcons[1] = new Image();
			this.arrIcons[1].src = this.imgFolder + 'plusbottom.gif';
			this.arrIcons[2] = new Image();
			this.arrIcons[2].src = this.imgFolder + 'minus.gif';
			this.arrIcons[3] = new Image();
			this.arrIcons[3].src = this.imgFolder + 'minusbottom.gif';
		} else {
			this.arrIcons[0] = new Image();
			this.arrIcons[0].src = this.imgFolder + 'nolines_plus.gif';
			this.arrIcons[1] = new Image();
			
			this.arrIcons[2] = new Image();
			this.arrIcons[2].src = this.imgFolder + 'nolines_minus.gif';
			this.arrIcons[3] = new Image();
			this.arrIcons[3].src = this.imgFolder + 'nolines_minus.gif';
		}
		this.arrIcons[4] = new Image();
		this.arrIcons[4].src = this.imgFolder + 'folder.gif';
		this.arrIcons[5] = new Image();
		this.arrIcons[5].src = this.imgFolder + 'folderopen.gif';
	}

	this.addNode = function(pNode)
	{
		for (var n=0; n<this.arrNodes.length; n++)
		{
			if (this.arrNodes[n].pid == pNode)
			{
				var cn = this.arrNodes[n];
				cn._hc = this.hasChildren(cn);
				cn._ls = (this.hasLines) ? this.lastSibling(cn) : false;
				if (cn._hc && !cn._io && this.useCookies) cn._io = this.isOpen(cn.id);
				if (this.clickSelect && cn.id == this.selectedNode)
				{
						cn._is = true;
						this.selectedInstance = n;
				}

				if (!this.folderLinks && cn._hc) cn.url = null;

				if (this.rootNode != cn.pid)
				{
					for (r=0; r<this.arrRecursed.length; r++)
						this.strOutput += '<img src="' + this.imgFolder + ( (this.arrRecursed[r] == 1 && this.hasLines) ? 'line' : 'empty' ) + '.gif" alt="" />';
					(cn._ls) ? this.arrRecursed.push(0) : this.arrRecursed.push(1);
					if (cn._hc)
					{
						this.strOutput += '<a href="javascript:' + this.instanceName + '.o(' + n + ');">'
							+ '<img id="j' + this.instanceName + n + '" src="' + this.imgFolder;
						if (!this.hasLines)
							this.strOutput += 'nolines_';
						this.strOutput += ( (cn._io) ? ((cn._ls && this.hasLines) ? 'minusbottom' : 'minus') : ((cn._ls && this.hasLines) ? 'plusbottom' : 'plus' ) )
							+ '.gif" alt="" /></a>';
					}
					else
						this.strOutput += '<img src="' + this.imgFolder + ( (this.hasLines) ? ((cn._ls) ? 'joinbottom' : 'join' ) : 'empty') + '.gif" alt="" />';
				}

				if (cn.url)
				{
					this.strOutput += '<a href="' + cn.url + '"';
					if (cn.title) this.strOutput += ' title="' + cn.title + '"';
					if (cn.target) this.strOutput += ' target="' + cn.target + '"';
					if (this.target && !cn.target) this.strOutput += ' target="' + this.target + '"';

					if (this.clickSelect)
					{
						if (cn._hc)
						{
							if (this.folderLinks)
								this.strOutput += ' onclick="' + this.instanceName + '.s(' + n + ')"';
						}
						else
						{
							this.strOutput += ' onclick="' + this.instanceName + '.s(' + n + ')"';
						}
					}
                                        if (cn.probe != '')
                                        {
                                            if ( cn.no_popup == 1)
                                            {
                                                this.strOutput += ' onmouseover="set_OBJ(' + cn.id + ',\'no_popup\')"';
                                            }
                                            else
                                            {
                                                this.strOutput += ' onmouseover="set_OBJ(' + (cn.id == 64010 ? 0 : cn.id) + ',\'' + cn.probe + '\')"';
                                            }
                                            this.strOutput += ' onmouseout="clear_OBJ()"';
                                        }
                                        else
                                        {
                                            if ( cn.no_popup == 1)
                                            {
                                                this.strOutput += ' onmouseover="set_OBJ(' + cn.id + ',\'no_popup\')"';
                                                this.strOutput += ' onmouseout="clear_OBJ()"';
                                            }
                                        }

					this.strOutput += '>';
				}
//alert(this.strOutput);
                                if (this.rootNode != cn.pid) {
				this.strOutput += '<img id="i' + this.instanceName + n + '" src="' + this.imgFolder;
				this.strOutput += (cn.img) ? cn.img : ((this.rootNode == cn.pid) ? 'base' : (cn._hc) ? ((cn._io) ? 'folderopen' : 'folder') : 'page') + '.gif';
				this.strOutput += '" alt="" />&nbsp;';
				this.strOutput += '<span id="s' + this.instanceName + n + '" class="' + ((this.clickSelect) ? ((cn._is ? 'nodeSel' : 'node')) : 'node') + '">';

				this.strOutput += cn.name;

				if (cn.id != '0' && this.hide_ip != 'true' && cn.ip ) {
                               		this.strOutput += '&nbsp;[' + cn.ip + ']'; 
                                }
					this.strOutput += '</span>';

				if (cn.url) this.strOutput += '</a>';
				if (cn.id != '0' 
                                    && this.hide_status != 'true' 
                                    && cn.no_status != 1 
                                    && cn.no_status_2 != 1 
                                    && cn.status != '') {
					this.strOutput += '&nbsp;<font id="s' + this.instanceName + n + '"class="st_' + cn.status + '">'
					if (cn.status == 0) this.strOutput += 'OK';
					if (cn.status == 1) this.strOutput += 'Warning';
					if (cn.status == 2) this.strOutput += 'Minor';
					if (cn.status == 3) this.strOutput += 'Major';
					if (cn.status == 4) this.strOutput += 'Down';
					if (cn.status == 5) this.strOutput += 'No SNMP';
					if (cn.status == 6) this.strOutput += 'Unreachable';
					if (cn.status == 64) this.strOutput += 'Unknown';
					if (cn.status == 123) this.strOutput += 'Recovered';
					if (cn.status == 124) this.strOutput += 'Init';
					if (cn.status == 125) this.strOutput += 'Info';
					if (cn.status == 126) this.strOutput += 'Bad configuration';
					if (cn.status == 127) this.strOutput += 'No status';
					this.strOutput += '</font>&nbsp;';
				}


				this.strOutput += '<br />\n';

                                }
				if (cn._hc)
				{
					this.strOutput += '<div id="d' + this.instanceName + n + '" style="display:'
					+ ((this.rootNode == cn.pid || cn._io) ? 'block' : 'none')
					+ ';">\n';
					this.addNode(cn.id);
					this.strOutput += '</div>\n';
				}
				this.arrRecursed.pop();
			}
		}
	}

	this.hasChildren = function(node)
	{
		for (n=0; n<this.arrNodes.length; n++)
			if (this.arrNodes[n].pid == node.id) return true;
		return false;
	}

	this.lastSibling = function(node)
	{
		var lastId;
		for (n=0; n< this.arrNodes.length; n++)
			if (this.arrNodes[n].pid == node.pid) lastId = this.arrNodes[n].id;
		if (lastId==node.id) return true;
		return false;
	}

	this.isOpen = function(id)
	{
		openNodes = this.getCookie('co' + this.instanceName).split('.');
		for (n=0;n<openNodes.length;n++)
			if (openNodes[n] == id) return true;
		return false;
	}

	this.getSelected = function(xselect)
	{
		selectedNode = xselect ? xselect : this.getCookie('cs' + this.instanceName);
		if (selectedNode)	return selectedNode;
		return null;
	}

	this.s = function(id)
	{
		cn = this.arrNodes[id];
		if (this.selectedInstance != id)
		{
			if (this.selectedInstance)
			{
				eOldSpan = document.getElementById("s" + this.instanceName + this.selectedInstance);
				eOldSpan.className = "node";
			}
			eNewSpan = document.getElementById("s" + this.instanceName + id);
			eNewSpan.className = "nodeSel";
			this.selectedInstance = id;
			if (this.useCookies) this.setCookie('cs' + this.instanceName, cn.id);
		}
	}

	this.o = function(id)
	{
		cn = this.arrNodes[id];
		(cn._io) ? this.nodeClose(id,cn._ls) : this.nodeOpen(id,cn._ls);
		cn._io = !cn._io;
		if (this.useCookies) this.updateCookie();
	}

	this.oAll = function(open)
	{
		for (n=0;n<this.arrNodes.length;n++)
		{
			if (this.arrNodes[n]._hc && this.arrNodes[n].pid != this.rootNode)
			{
				if (open)
				{
					this.nodeOpen(n, this.arrNodes[n]._ls);
					this.arrNodes[n]._io = true;
				}
				else
				{
					this.nodeClose(n, this.arrNodes[n]._ls);
					this.arrNodes[n]._io = false;
				}
			}
		}
		if (this.useCookies) this.updateCookie();
	}

	this.nodeOpen = function(id, bottom)
	{
		eDiv	= document.getElementById('d' + this.instanceName + id);
		eJoin	= document.getElementById('j' + this.instanceName + id);
		eIcon	= document.getElementById('i' + this.instanceName + id);
		eJoin.src = (bottom) ?	this.arrIcons[3].src : this.arrIcons[2].src;
		if (!this.arrNodes[id].img) eIcon.src = this.arrIcons[5].src;
		eDiv.style.display = 'block';
	}

	this.nodeClose = function(id, bottom)
	{
		eDiv	= document.getElementById('d' + this.instanceName + id);
		eJoin	= document.getElementById('j' + this.instanceName + id);
		eIcon	= document.getElementById('i' + this.instanceName + id);
		eJoin.src = (bottom) ? this.arrIcons[1].src : this.arrIcons[0].src;
		if (!this.arrNodes[id].img) eIcon.src = this.arrIcons[4].src;
		eDiv.style.display = 'none';
	}

	this.clearCookie = function()
	{
		var now = new Date();
		var yesterday = new Date(now.getTime() - 1000 * 60 * 60 * 24);
		this.setCookie('co'+this.instanceName, 'cookieValue', yesterday);
		this.setCookie('cs'+this.instanceName, 'cookieValue', yesterday);
	}

	this.setCookie = function(cookieName, cookieValue, expires, path, domain, secure) {
		document.cookie =
			escape(cookieName) + '=' + escape(cookieValue)
			+ (expires ? '; expires=' + expires.toGMTString() : '')
			+ (path ? '; path=' + path : '')
			+ (domain ? '; domain=' + domain : '')
			+ (secure ? '; secure' : '');
	}

	this.getCookie = function(cookieName) {
		var cookieValue = '';
		var posName = document.cookie.indexOf(escape(cookieName) + '=');
		if (posName != -1)
		{
			var posValue = posName + (escape(cookieName) + '=').length;
			var endPos = document.cookie.indexOf(';', posValue);
			if (endPos != -1)
				cookieValue = unescape(document.cookie.substring(posValue, endPos));
			else
				cookieValue = unescape(document.cookie.substring(posValue));
		}
		return (cookieValue);
	}

	this.hide_status = this.getCookie('AKKADA_HIDE_STATUS') || false;
	this.hide_ip = this.getCookie('AKKADA_HIDE_IP') || false;
	this.tree_sort = this.getCookie('AKKADA_TREE_SORT') || false;

	this.updateCookie = function()
	{
		sReturn = '';
		for (n=0;n<this.arrNodes.length;n++)
		{
			if (this.arrNodes[n]._io && this.arrNodes[n].pid != this.rootNode)
			{
				if (sReturn) sReturn += '.';
				sReturn += this.arrNodes[n].id;
			}
		}
		this.setCookie('co' + this.instanceName, sReturn);
	}

}

if (!Array.prototype.push) {
	Array.prototype.push = function array_push() {
		for(var i=0;i<arguments.length;i++)
			this[this.length]=arguments[i];
		return this.length;
	}
}
if (!Array.prototype.pop) {
	Array.prototype.pop = function array_pop() {
		lastElement = this[this.length-1];
		this.length = Math.max(this.length-1,0);
		return lastElement;
	}
}

