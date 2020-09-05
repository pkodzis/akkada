
Akkada.TabPanel = function(config){
    Akkada.TabPanel.superclass.constructor.call(this, config);
};

Ext.extend(Akkada.TabPanel, Ext.TabPanel, {
    akState: null
    ,layoutOnTabChange:true
    ,addEntTab: function(id, text, section) {
        this.add(new Akkada.TabPanelTab({
            title: text
            ,akType:'entity'
            ,akEid: id
            ,akSection: section
            ,id: this.getEntId(id, section)
        })).show();
    }
    //,stateEvents: ['tabchange']  // !!!! odkomentowac jak problem bedzie rozwiazany
    ,getEntId: function(id, section) {
        return 'entity-' + id + '-' + section;
    }
    ,getState: function() {
        var st = [];
        var i = 0;
        var active_item = this.getActiveTab();
        var t = '';
        this.items.each(function(){
            t = '[' + this.akSection + ']';
            st[i] = {
                id: this.id
                ,title: this.akType == 'entity' ? this.title.substr(0,this.title.indexOf(t)) : this.title
                ,akType: this.akType
                ,akEid: this.akEid
                ,akSection: this.akSection
                ,active: active_item == this ? 1 : 0
            };
            i++;
        });
        return st;
    }
    ,applyState: function(state) {
        this.akState = state;
        Akkada.TabPanel.superclass.applyState.apply(this, arguments);
    }
    ,stateRestore: function() {
        var state = this.akState;
        if (!state) {
            return;
        }
        var active_item;
        for (var i=0; i<state.length; i++) {
            if (!Ext.getCmp(state[i].id) && state[i].akType == 'entity') {
                this.addEntTab(state[i].akEid,state[i].title, state[i].akSection);
            }
            if (! active_item && state[i].active == 1) {
               active_item = state[i].id;
            }
        };
        this.setActiveTab(active_item);
    }

}); // eof class Akkada.TabPanel

Ext.reg('akkada-tabpanel', Akkada.TabPanel);


