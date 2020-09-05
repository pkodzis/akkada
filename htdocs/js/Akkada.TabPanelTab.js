/*
 * AKK@Da 2.0
 * Copyright(c) 2005-2009, Piotr Kodzis
 * 
 * This is Open Source software. You can redistribute it 
 * and/or modify it under the terms of the GNU General Public License 
 * as published by the Free Software Foundation, either 
 * version 2 of the License or any later version. 
 *
 * http://akkada.tivi.net.pl
 */



/*
 * required config options:
 *  akType: string 'entity', 'home'
 *  akSection: strinf 'general', 'alarms', etc
 *  akEid: int entity ID
 *
 */
Akkada.TabPanelTab = Ext.extend(Ext.Container, {
    initComponent: function() {
        Ext.apply(this, {
            title: this.title +' ['+this.akSection+']'
            ,akSection: this.akSection
            ,closable: true
/*
            ,layout: 'table'
            ,layoutConfig: {
                columns: 1
            }
*/
            ,akEntGenInfo: null
            ,getEgiId: function(id, section) {
                return 'ak-egi-' + id + '-' + section;
            }
            ,getEntGenInfo: function () {
                if (this.akEntGenInfo) {
                    this.akEntGenInfo.store.reload();
                } else {
                    var eid = this.akEid;
                    this.akEntGenInfo = new Akkada.EntGenInfo({id: this.getEgiId(eid, this.akSection), eid: eid});
                    this.akEntGenInfo.store.load();
                }
            } // eo function getEntGenInfo
            ,afterRender: function() {
                Akkada.TabPanelTab.superclass.afterRender.apply(this, arguments);
                this.rebuildContent()
            } // eo function afterRender
            ,rebuildContent: function() {
                this.getEntGenInfo();
                if (this.akEntGenInfo) {
                    if (! Ext.getCmp(this.getEgiId(this.eid, this.akSection))) {
                        this.add(this.akEntGenInfo);
                    }
                    /*this.add(new Ext.form.Label({text:'row 2'}));
                    this.add(new Ext.form.Label({text:'row 3'}));
                    this.add(new Ext.form.Label({text:'row 4'}));*/
                } else {
                    alert('cannot load general information for entitiy ' + this.akEid);
                }
            } // eo function rebuildContent
        }); // eo function apply
        Akkada.TabPanelTab.superclass.initComponent.apply(this, arguments);
    } // ef function initComponent
}); // eo class Akkada.TabPanelTab

Ext.reg('akkada-tabpanel-tab', Akkada.TabPanelTab);


