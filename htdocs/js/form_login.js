Ext.onReady(function(){
    Ext.QuickTips.init();

    var login;

    var doSubmit = function(){
                    login.getForm().submit({
                        method:'POST',
                        waitTitle:'Connecting',
                        waitMsg:'Sending data...',
                        success:function(){
                            window.location = '/ws';
                        },
                        failure:function(form, action){
                            if(action.failureType == 'server'){
                                obj = Ext.util.JSON.decode(action.response.responseText);
                                Ext.getCmp('ak-form_login-status').getEl().update(obj.errors.reason);
                            }else{
                                Ext.getCmp('ak-form_login-status').getEl().update('Authentication server is unreachable');
                            }
                            //login.getForm().reset();
                            doFocus();
                        }
                    });
        };

    var doFocus = function(){
        var field = login.getForm().findField('username');
        field.focus.defer(100,field);
    };
 
    login = new Ext.FormPanel({ 
        labelWidth:80,
        url:'/ws/process_form_login', 
        frame:true, 
        title:'Please Login', 
        defaultType:'textfield',
	monitorValid:true,
	// Specific attributes for the text fields for username / password. 
	// The "name" attribute defines the name of variables sent to the server.
        items:[{ 
                fieldLabel:'Username', 
                name:'username', 
                allowBlank:false 
            },{ 
                fieldLabel:'Password', 
                name:'password', 
                inputType:'password', 
                allowBlank:false 
            }],
 
	// All the magic happens after the user clicks the button     
        buttons:[{ 
                text:'Login',
                formBind: true,	 
                handler: doSubmit
            }],
        keys: [{
            key: Ext.EventObject.ENTER,
            fn: doSubmit
        }]
       ,bbar: new Ext.Panel({items:[{id:'ak-form_login-status',xtype:'box',cls:'ak-text-red',autoEl:{cn:''}}]})
    });
 
    var win = new Ext.Window({
        layout:'fit',
        width:300,
        height:150,
        closable: false,
        resizable: false,
        plain: true,
        border: false,
        items: [login]
	});
        win.on('show',doFocus,win);
	win.show();
});
