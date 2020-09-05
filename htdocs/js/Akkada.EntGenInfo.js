var expander = new Akkada.TabPanelRowExpander({}, 'info');

Akkada.EntGenInfo = Ext.extend(Ext.grid.GridPanel, {
    border:false
    ,stripeRows: true
    ,hideHeaders:false
    ,trackMouseOver:false
    ,disableSelection:true
    ,enableHdMenu:false
    ,enableDragDrop:false
    ,enableColumnMove:false
    ,enableColumnResize:false
    ,plugins: expander
    ,autoHeight:true
    ,width:1
    ,style: 'text-align:left;'
    ,initComponent:function() {
        Ext.apply(this, {
            store:new Ext.data.Store({
                id: this.id + '-store'
                ,proxy: new Ext.data.HttpProxy({
                    url: 'wstree/entgeninfo'
                    ,method: 'POST'
                }) // eo HttpProxy
                ,baseParams: {eid: this.eid }
                ,reader: new Ext.data.JsonReader({   
                    root: 'results'
                    ,idProperty: 'eid'
                    ,fields: [
                        {name:'eid',type:'int'}
                        ,{name:'vendor',type:'string'}
                        ,{name:'name',type:'string'}
                        ,{name:'status',type:'string'}
                        ,{name:'statusid',type:'int'}
                        ,{name:'function',type:'string'}
                        ,{name:'last_change',type:'string'}
                        ,{name:'last_check',type:'string'}
                        ,{name:'info',type:'string'}
                    ] 
                }) // eo JsonReader
              //,sortInfo:{field: 'name', direction: "ASC"}
                ,listeners: {
                    scope: this,
		    'load': function(){
			this.autoSizeColumns();
                        expander.expandRow(0);
                        Ext.getCmp('ak-sb').stopLoading();
                    },
		    'beforeload': function(){
                        Ext.getCmp('ak-sb').startLoading();
                    }
                } // eo listeners
            }) // eo store
            ,columns: [
                expander
                ,{id:'vendor',header: '&nbsp;', sortable: false, dataIndex: 'vendor'
                    ,renderer: function(data, cell, record, rowIndex, columnIndex, store){
                        if (/*rowIndex == 0 || */store.getAt(rowIndex).get('vendor') == '') {
                            return '';
                        }
                        cell.css = 'ak-td-img';
                        return data;
                    } // eo function renderer
                }
                ,{id:'name',header: 'name', sortable: false, dataIndex: 'name'}
                ,{id:'status',header: 'status', sortable: false, dataIndex: 'status'
                    ,renderer: function(data, cell, record, rowIndex, columnIndex, store){
                        /*if (rowIndex == 0) {
                            return '';
                        }*/
                        cell.css = 'ak-td-st-' + store.getAt(rowIndex).get('statusid');
                        return data;
                    } // eo function renderer
                }
                ,{id:'function',header: '&nbsp;', sortable: false, dataIndex: 'function'
                    ,renderer: function(data, cell, record, rowIndex, columnIndex, store){
                        if (/*rowIndex == 0 ||*/ store.getAt(rowIndex).get('function') == '') {
                            return '';
                        }
                        cell.css = 'ak-td-img';
                        return data;
                    } // eo function renderer
                }
                ,{id:'last_change',header: 'last change', sortable: false, dataIndex: 'last_change'}
                ,{id:'last_check',header: 'age of data', sortable: false, dataIndex: 'last_check'}
            ] // eo columns
	    ,cellPadding: 4
	    ,autoSizeColumn: function(colIndex) {
                var sz = 0;
                var el, w;
                var gv = this.getView();
                    el = Ext.fly(gv.getHeaderCell(colIndex)); // cell element <td>
                    w = el.getWidth(); // get cell width
                    el = el.first('div.x-grid3-hd-inner'); // inner cell element <td><div>
                    w -= el.getWidth(true); // subtract inner cell width, content only (keep borders, margins, paddings... from cell and inner cell elements)
                    w += el.getTextWidth(Ext.util.Format.stripTags(el.innerHTML)); // add width of content
                    if (w > sz) sz = w; // use biggest value
                for (i = 0; i < this.store.getTotalCount(); i++) {
                    el = Ext.fly(gv.getCell(i, colIndex)); // cell element <td>
                    w = el.getWidth(); // get cell width
                    el = el.first('div.x-grid3-cell-inner'); // inner cell element <td><div>
                    w -= el.getWidth(true); // subtract inner cell width, content only (keep borders, margins, paddings... from cell and inner cell elements)
                    w += el.getTextWidth(Ext.util.Format.stripTags(el.innerHTML)); // add width of content
                    if (w > sz) sz = w; // use biggest value
                }
                // set biggest value as width of the column
                this.getColumnModel().setColumnWidth(colIndex, sz);
                return sz;
            //    gv.fireEvent('columnresize', colIndex, sz);
	    } // eo function autoSizeColumn
            ,autoSizeColumns: function() {
                var sz = 0;
                for (var c = 1, len = this.getColumnModel().getColumnCount(); c < len; c++) {
                    sz += this.autoSizeColumn(c);
                }
                this.setWidth(sz+24);
            } // eo function autoSizeColumns
            ,viewConfig: {
                headersDisabled: true 
            } //eo viewConfig
        });
        Akkada.EntGenInfo.superclass.initComponent.apply(this, arguments);
    } // eo function initComponent
}); // eo Akkada.EntGenInfo
 
Ext.reg('akkada-entgeninfo', Akkada.EntGenInfo);

