
Akkada.StatusBar = function(config){
    Ext.apply(this, {
        region:'south',
        id:'ak-sb',
        height:29,
        loadingQueue: 0,
        items: [
            new Ext.Toolbar({
                items: [
                    new Ext.Container({
                        width: 100,
                        layout: 'table',
                        items: [
                            new Ext.BoxComponent({
                                id: 'ak-sb-loading-icon',
                                height: 22,
                                cls: 'ak-sb-idle',
                                autoEl: {tag:'div'}
                            })
                            ,{xtype: 'tbtext', text: 'Idle', id: 'ak-sb-loading-text'}
                        ]
                    })
                    ,{xtype: 'tbseparator'}
                ]
            })
        ]
    });
    Akkada.StatusBar.superclass.constructor.call(this, config);
};

Ext.extend(Akkada.StatusBar, Ext.Panel, {
    startLoading: function() {
        if (this.loadingQueue == 0) {
            var st = Ext.get('ak-sb-loading-icon');
            st.removeClass('ak-sb-idle');
            st.addClass('ak-loading-indicator');
            st = Ext.get('ak-sb-loading-text');
            st.dom.innerHTML = 'Loading data...';
        }
        this.loadingQueue++;
    }
    ,stopLoading: function() {
        if (this.loadingQueue > 0) {
            this.loadingQueue--;
        } else { 
            alert('statusbar loading < 0 problem'); 
        }
        if (this.loadingQueue == 0) {
            var st = Ext.get('ak-sb-loading-icon');
            st.removeClass('ak-loading-indicator');
            st.addClass('ak-sb-idle');
            st = Ext.get('ak-sb-loading-text');
            st.dom.innerHTML = 'Idle';
        }
    }
}); // eof class Akkada.StatusBar

/*
*/

Ext.reg('akkada-statusbar', Akkada.StatusBar);


