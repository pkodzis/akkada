// class Akkada.TabPanelRowExpander

Akkada.TabPanelRowExpander = function(config, field){
    Akkada.TabPanelRowExpander.superclass.constructor.call(this, config);
    this.field = field;
    this.enableCaching = false;
};

Ext.extend(Akkada.TabPanelRowExpander, Ext.grid.RowExpander, {
    getBodyContent: function(record, index){
        return record.get(this.field);
    } // eo function getBodyContent
    ,beforeExpand: function(record, body, rowIndex){
        if(this.fireEvent('beforeexpand', this, record, body, rowIndex) !== false){
            Ext.getCmp('ak-sb').startLoading();
            Ext.Ajax.request({
                url:'/wstree/entinfo',
                params:{eid: record.id},
                success:function(response, request) {
                    if (response.responseText.charAt(0) == 2){
                        window.location = '/ws';
                    } else if (response.responseText.charAt(0) != 1){
                        body.innerHTML = '<p>' + response.responseText;
                    }
                }, // eo function success
                failure:function(response, request) {
                    body.innerHTML = 'Failed to contact server.';
                } // eo function failure
            }); // eo Ext.Ajax.request
            Ext.getCmp('ak-sb').stopLoading();
            return true;
        } else{
            return false;
        }
    } // eo function beforeExpand
}); // eof class Akkada.TabPanelRowExpander

Ext.reg('akkada-tabpanel-rowexpander', Akkada.TabPanelRowExpander);

