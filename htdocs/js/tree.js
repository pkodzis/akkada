var akTree = function(){

    var Tree = Ext.tree;

    var akTreeMenu = new Ext.menu.Menu({
        id: 'akTreeMenu'
        ,useIcons: false
        ,items: [{
            text: 'General'
            ,id: 'general'
            ,handler: akTreeMenuOnClick
        }
        ,{
            text: 'Alarms'
            ,id: 'alarms'
            ,handler: akTreeMenuOnClick
        }
        ,{
            text: 'Options'
            ,id: 'options'
            ,handler: akTreeMenuOnClick
        }
        ,{
            text: 'Open in new tab'
            ,menu: {
                items: [{
                    id: 'general-new'
                    ,text: 'General'
                    ,handler: akTreeMenuOnClick
                }
                ,{
                    id: 'alarms-new'
                    ,text: 'Alarms'
                    ,handler: akTreeMenuOnClick
                }
                ,{
                    id: 'options-new'
                    ,text: 'Options'
                    ,handler: akTreeMenuOnClick
                }]
            }
        }]
    }); // eo akTreeMenu

    function akTreeMenuOnClick(item, e) {
        var node = Ext.getCmp('ak-tree').getSelectionModel().getSelectedNode();
        var tabs = Ext.getCmp('ak-panel-center');
        var tab = tabs.getItem(tabs.getEntId(node.id,item.text));

        if (tab) { 
            tabs.activate(tab.id);
            tabs.getActiveTab().rebuildContent();
        } else if (item.id.indexOf('-new') > -1) {
            tabs.addEntTab(node.id,node.text,item.text);
        } else {
            tab = tabs.getActiveTab();
            if (tab.akType == 'entity') {
                tabs.remove(tab);
            }
            tabs.addEntTab(node.id,node.text,item.text);
        }
    } // eo function akTreeMenuOnClick

    return {
        init : function(){

            var tree = new Tree.TreePanel({
                el:'tree',
                id: 'ak-tree',
                animate:true,
                autoScroll:true,
                loader: new Tree.TreeLoader({
                    dataUrl:'/wstree'
                    ,baseAttrs: {uiProvider: Akkada.TreeNodeUI}
                }),
                enableDD:true,
                rootVisible:true,
                bodyBorder:false,
                containerScroll:true
            }); // eo tree

            new Tree.TreeSorter(tree, {folderSort:true});

            var root = new Tree.AsyncTreeNode({
                id:'0',
                uiProvider: Akkada.TreeNodeUI,
                text: 'locations'
            });
            tree.setRootNode(root);

            tree.render();

            //root.expand(false, false);

            var oldPosition = null;
            var oldNextSibling = null;

            tree.on('contextmenu', this.menuShow, this);

            tree.on('startdrag', function(tree, node, event){
                oldPosition = node.parentNode.indexOf(node);
                oldNextSibling = node.nextSibling;
            }); // eo function startdrag

            tree.on('click', function(node, e) {
                if (node.id == 0) {
                    return;
                }
                var tabs = Ext.getCmp('ak-panel-center');
                var tab = tabs.getActiveTab();
                section = tab.akType == 'entity' ? tab.akSection : 'general';
                akTreeMenuOnClick(akTreeMenu.items.get(section.toLowerCase()),e);
            }); // of function click

            tree.on('beforeload', function() {
                Ext.getCmp('ak-sb').startLoading();
            }); // of function beforeload

            tree.on('load', function() {
                Ext.getCmp('ak-sb').stopLoading();
            }); // of function load


            tree.on('movenode', function(tree, node, oldParent, newParent, position){
                if (oldParent == newParent){
                    return;
                } else {
                    var params = {'node':node.id, 'parent':newParent.id, 'position':position};
                }
    
                tree.disable();
    
                Ext.Ajax.request({
                    url:'/wstree/move',
                    params:params,
                    success:function(response, request) {
                        if (response.responseText.charAt(0) == 2){
                            window.location = '/ws';
                        } else if (response.responseText.charAt(0) != 1){
                            Ext.Msg.show({
                                closable: false,
                                title: 'ERROR',
                                icon: Ext.Msg.ERROR,
                                msg: response.responseText,
                                buttons: Ext.Msg.OK
                            });
                        } else {
                            tree.enable();
                        }
                    }, // eo function success
                    failure:function(response, request) {
                        Ext.Msg.show({
                            closable: false,
                            title: 'ERROR',
                            icon: Ext.Msg.ERROR,
                            msg: 'Failed to contact server.',
                            buttons: Ext.Msg.OK
                        });            

                        tree.suspendEvents();
                        oldParent.appendChild(node);
                        if (oldNextSibling){
                            oldParent.insertBefore(node, oldNextSibling);
                        }
            
                        tree.resumeEvents();
                        tree.enable();
                    } // eo function failure
                }); // eo Ext.Ajax.request
            }); // eo function movenode
        } // eo function init
        ,menuShow : function( node ){
            if (node.id == 0) {
                return;
            };
            node.select();
            akTreeMenu.show(node.ui.getEl());
        }
    };
}(); // eo akTree


