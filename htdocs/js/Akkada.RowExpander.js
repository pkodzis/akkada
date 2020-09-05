Ext.grid.RowExpander = function(config){
    Ext.apply(this, config);
    Ext.grid.RowExpander.superclass.constructor.call(this);

    if(this.tpl){
        if(typeof this.tpl == 'string'){
            this.tpl = new Ext.Template(this.tpl);
        }
        this.tpl.compile();
    }

    this.state = {};
    this.bodyContent = {};

    this.addEvents({
        beforeexpand : true,
        expand: true,
        beforecollapse: true,
        collapse: true
    });
};

Ext.extend(Ext.grid.RowExpander, Ext.util.Observable, {
    header: "",
    width: 20,
    sortable: false,
    fixed:true,
    dataIndex: '',
    id: 'expander',
    lazyRender : true,
    enableCaching: true,

    getRowClass : function(record, rowIndex, p, ds){
        p.cols = p.cols-1;
        var content = this.bodyContent[record.id];
        if(!content && !this.lazyRender){
            content = this.getBodyContent(record, rowIndex);
        }
        if(content){
            p.body = content;
        }
        return this.state[record.id] ? 'x-grid3-row-expanded' : 'x-grid3-row-collapsed';
    },

    init : function(grid){
        this.grid = grid;

        var view = grid.getView();
        view.getRowClass = this.getRowClass.createDelegate(this);

        view.enableRowBody = true;

        grid.on('render', function(){
            view.mainBody.on('mousedown', this.onMouseDown, this);
        }, this);
    },

    getBodyContent : function(record, index){
        if(!this.enableCaching){
            return this.tpl.apply(record.data);
        }
        var content = this.bodyContent[record.id];
        if(!content){
            content = this.tpl.apply(record.data);
            this.bodyContent[record.id] = content;
        }
        return content;
    },
	// Setter and Getter methods for the remoteDataMethod property
	setRemoteDataMethod : function (fn){
		this.remoteDataMethod = fn;
	},
	
	getRemoteDataMethod : function (record, index){
		if(!this.remoteDataMethod){
			return;
		}
			return this.remoteDataMethod.call(this,record,index);
	},

    onMouseDown : function(e, t){
        if(t.className == 'x-grid3-row-expander'){
            e.stopEvent();
            var row = e.getTarget('.x-grid3-row');
            this.toggleRow(row);
        }
    },

    renderer : function(v, p, record){
        //if (record.id == 0) {
        //    return '';
        //}
        p.cellAttr = 'rowspan="2"';
        return '<div class="x-grid3-row-expander">&#160;</div>';
    },

    beforeExpand : function(record, body, rowIndex){
        if(this.fireEvent('beforexpand', this, record, body, rowIndex) !== false){
            // If remoteDataMethod is defined then we'll need a div, with a unique ID,
            //  to place the content
			if(this.remoteDataMethod){
				this.tpl = new Ext.Template("<div id='remData" + rowIndex + "' class='rem-data-expand'><\div>");
			}
			if(this.tpl && this.lazyRender){
                body.innerHTML = this.getBodyContent(record, rowIndex);
            }
			
            return true;
        }else{
            return false;
        }
    },
	
	toggleRow : function(row){
        if(typeof row == 'number'){
            row = this.grid.view.getRow(row);
        }
        this[Ext.fly(row).hasClass('x-grid3-row-collapsed') ? 'expandRow' : 'collapseRow'](row);
    },

    expandRow : function(row){
        if(typeof row == 'number'){
            row = this.grid.view.getRow(row);
        }
        var record = this.grid.store.getAt(row.rowIndex);
        var body = Ext.DomQuery.selectNode('tr:nth(2) div.x-grid3-row-body', row);
        if(this.beforeExpand(record, body, row.rowIndex)){
            this.state[record.id] = true;
            Ext.fly(row).replaceClass('x-grid3-row-collapsed', 'x-grid3-row-expanded');
           	if(this.fireEvent('expand', this, record, body, row.rowIndex) !== false){
				//  If the expand event is successful then get the remoteDataMethod
				this.getRemoteDataMethod(record,row.rowIndex);
			}
        }
    },

    collapseRow : function(row){
        if(typeof row == 'number'){
            row = this.grid.view.getRow(row);
        }
        var record = this.grid.store.getAt(row.rowIndex);
        var body = Ext.fly(row).child('tr:nth(1) div.x-grid3-row-body', true);
        if(this.fireEvent('beforcollapse', this, record, body, row.rowIndex) !== false){
            this.state[record.id] = false;
            Ext.fly(row).replaceClass('x-grid3-row-expanded', 'x-grid3-row-collapsed');
            this.fireEvent('collapse', this, record, body, row.rowIndex);
        }
    }
}); // eo class Ext.grid.RowExtender

// class Akkada.RowExpander

Akkada.RowExpander = function(config, field){
    Akkada.RowExpander.superclass.constructor.call(this, config);
    this.field = field;
    this.enableCaching = false;
};

Ext.extend(Akkada.RowExpander, Ext.grid.RowExpander, {
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
}); // eof class Akkada.RowExpander

Ext.reg('akkada-rowexpander', Akkada.RowExpander);

