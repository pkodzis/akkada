Ext.ns('Akkada');
Ext.BLANK_IMAGE_URL = '/ext/resources/images/default/s.gif';
Ext.state.Manager.setProvider(new Ext.state.CookieProvider()); 

Ext.onReady(function(){

    Ext.state.Manager.setProvider(new Ext.state.CookieProvider());

    var north = new Ext.BoxComponent({
        region:'north',
        el: 'north',
        height:32
    });

    var center = new Akkada.TabPanel({
        region:'center',
        deferredRender:false,
        layoutOnTabChange:true,
        id:'ak-panel-center',
        activeTab:0,
        resizeTabs:false, 
        autoWidth:true,
        enableTabScroll:true,
        defaults: {autoScroll:true},
        plugins: new Ext.ux.TabCloseMenu(),
        items:[{
            id:'ak-panel-center-tab-home',
            title: 'AKK@DA home',
            autoScroll:true
            ,akType:'home'
        }]
    });


    var west = new Ext.Panel({
        region:'west',
        id:'ak-panel-west',
        title:'Navigation',
        split:true,
        width: 200,
        minSize: 175,
        maxSize: 400,
        collapsible: true,
        margins:'0 0 0 0',
        layout:'accordion',
        autoScroll:false,
        layoutConfig:{
            animate:true
        },
        items: [{
            id:'ak-panel-west-tab-tree',
            contentEl: 'west',
            title:'Tree',
            border:false,
            autoScroll:true,
            html:'<div id="tree"></div>'
            //iconCls:'nav'

        },{
            id:'ak-panel-west-tab-views',
            contentEl: 'west',
            title:'Views',
            autoScroll:false,
            border:false,
            html:'<div id="views"></div>'
            //iconCls:'settings'
        }]
    });

    var statusbar = new Akkada.StatusBar({id: 'ak-sb'});

    var viewport = new Ext.Viewport({
        layout:'border',
        items:[ north, west, center, statusbar ]
    });

    Ext.EventManager.onDocumentReady(akTree.init, akTree, true);
    Ext.getCmp('ak-panel-center').stateRestore();

/*
// to capture events for a particular component:
Ext.util.Observable.capture(
    Ext.getCmp('ak-tree'),
    function(e) {
        console.info(e);
    }
);
*/

}); // eo function onReady

