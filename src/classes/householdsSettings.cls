/*
    Copyright (c) 2011, Salesforce.com Foundation
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Salesforce.com Foundation nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
 
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.com Foundation
* @date 2011 (2.0)
* @description The controller for the Household Settings VF page 
*/
public with sharing class householdsSettings {
    
    public Households_Settings__c pageSettings = new Households_Settings__c();
    public boolean runningBatch {get; set;}
    
     /********Vars for PKG Update Info *************/
    public string getMyVersion(){return string.valueof(Package.Version.Request);}
    public string getMaxVersion(){return pageSettings.Max_Package_Version__c;}
    public string getUpdateURL(){return pageSettings.Package_Update_URL__c;}
    public string getLastUpdate(){      
        DateTime d = pageSettings.Last_Update_Check__c;
        string datestring = '';
        if (d != null)
            datestring = d.format('MMMMM dd, yyyy hh:mm:ss a');
        return datestring;
    }
    public string getpkgupdatestatus(){
        string status = pageSettings.Has_Package_Update__c;
        if (status == 'true')
           status = 'New Update Available';
        else if (status == 'false')
           status = 'No New Updates Available';
        else
           status = status;
           
        return status;
    }
    /*********************************************/
    
    
    public householdsSettings(){
        acctRTs = new List<string>();
        acctTypes = new List<string>();
        contactRTs = new List<string>();
        contactTypes = new List<string>();
        if (runningbatch == null)
            runningbatch = false;
    }
    
    public Households_Settings__c getSettings() {
        pageSettings = Households.getHouseholdsSettings();
        return pageSettings;
    }
    //we can't do a DML in a getter, so I call it from the action of the page
    public PageReference getSettingsFirstTime() {
    	   
        //set a null page reference
        PageReference pr = null;    	    	
    	
    	//if we don't have default settings
    	if (Households_Settings__c.getOrgDefaults() == null){
    	   pageSettings = Households.getHouseholdsSettings();
    	   
    	   //no point in scheduling a rollup, since the default
    	   //has it disabled, just call a page refresh to get to the 
    	   //callout    	   
    	   pr = ApexPages.currentPage();
    	}
    	
    	//we can safely call out to 
    	else{
    	   pageSettings = Households.getHouseholdsSettings();
    	   pr = scheduleRollups();
    	   if (pr == null){
    	   	   //else if we don't need to update anything, we 
                //can go ahead and callout for update checks
                if (pageSettings.Last_Update_Check__c == null){
                    checkforupdates();
                }
            }
        }    	   
    	        
        //set the multi-select fields
        if(pageSettings.npo02__Excluded_Account_Opp_Types__c!=null){
        	acctTypes = pageSettings.npo02__Excluded_Account_Opp_Types__c.split(';',0);
        }
        
         if(pageSettings.npo02__Excluded_Contact_Opp_Types__c!=null){
        	contactTypes = pageSettings.npo02__Excluded_Contact_Opp_Types__c.split(';',0);
        }
        
         if(pageSettings.npo02__Excluded_Account_Opp_Rectypes__c!=null){
        	acctRTs = pageSettings.npo02__Excluded_Account_Opp_Rectypes__c.split(';',0);
        }
        
         if(pageSettings.npo02__Excluded_Contact_Opp_Rectypes__c!=null){
        	contactRTs = pageSettings.npo02__Excluded_Contact_Opp_Rectypes__c.split(';',0);
        }
        
        
        if (pr != null){
        	pr.setRedirect(true);
        }
            
        return pr;
    }
    
    public List<SelectOption> contactRoles = new List<SelectOption>();
    public List<String> acctRTs {get;set;}
    public List<String> acctTypes {get;set;}
    public List<String> contactRTs {get;set;}
    public List<String> contactTypes {get;set;}
    
    public List<SelectOption> getcontactRoles() {
    
        if(contactRoles.size()==0){
            contactRoles.add(new SelectOption(' ','- none -'));
            Schema.DescribeFieldResult F = Schema.sObjectType.OpportunityContactRole.fields.Role; 
            List<Schema.PicklistEntry> P = F.getPicklistValues();
            for(Schema.PicklistEntry pe : P){
                contactRoles.add(new SelectOption(pe.getLabel(), pe.getLabel()));
            }
        }
        return contactRoles;
    }
    
    List<SelectOption> householdrules;
    List<SelectOption> RTypes;
    List<SelectOption> Types;
    List<SelectOption> oppStages = new List<SelectOption>();
   
    public PageReference scheduleRollups(){
    	PageReference pr = null;
    	
        if(pageSettings.Enable_Opp_Rollup_Triggers__c){
            Integer scheduledJobLimit = 10;
            boolean alreadyScheduled = false;            
            
            List<cronTrigger> scheduledRollups = [SELECT Id FROM cronTrigger limit :scheduledJobLimit];
            
            if(pageSettings.Opp_Rollup_Scheduled_Job_Id__c != null){
                for(cronTrigger thisScheduledJob : scheduledRollups){ 
                    if(thisScheduledJob.id == pageSettings.Opp_Rollup_Scheduled_Job_Id__c){
                        alreadyScheduled = true;
                        break;
                    }
                }
            }
            
            if(!alreadyScheduled){
                if(scheduledRollups.size()<scheduledJobLimit){     
                	
                    SCHED_OppRollup rollUp = new SCHED_OppRollup(); 
                    //need to check for already scheduled job
                    String sch='17 11 2 * * ?'; 
                    scheduledRollups.clear();
					scheduledRollups = [SELECT Id FROM cronTrigger where cronExpression = :sch];
					if (scheduledRollups.size()==0){
                    	String jobId = system.schedule('Nightly Opportunity Roll Up', sch ,rollUp);
                    	pageSettings.Opp_Rollup_Scheduled_Job_Id__c = jobId;
	                	
					} else {
						pageSettings.Opp_Rollup_Scheduled_Job_Id__c = scheduledRollups[0].Id;
					}
					//if we update page settings, we need to call a redirect
                    update pageSettings;
                	pr = ApexPages.currentPage();
                	
                } else {
                    showMsg(Label.Opportunity_Rollup_Scheduling_Error_Text, ApexPages.Severity.FATAL);
                }
            }    
        }
        return pr;
    }

    public List<SelectOption> gethouseholdrules() {
        if(householdrules == null){
            householdrules = new List<SelectOption>();
            householdrules.add(new SelectOption(Households.ALL_PROCESSOR, Households.ALL_PROCESSOR));
            householdrules.add(new SelectOption(Households.ALL_INDIVIDUALS_PROCESSOR, Households.ALL_INDIVIDUALS_PROCESSOR));
            householdrules.add(new SelectOption(Households.NO_HOUSEHOLDS_PROCESSOR, Households.NO_HOUSEHOLDS_PROCESSOR));
        }
        return householdrules;
    }
    
     public List<SelectOption> getoppStages() {
        
    
        if(oppStages.size()==0){
            oppStages.add(new SelectOption(' ','- none -'));
            Schema.DescribeFieldResult F = Schema.sObjectType.Opportunity.fields.StageName; 
            List<Schema.PicklistEntry> P = F.getPicklistValues();
            for(Schema.PicklistEntry pe : P){
                oppStages.add(new SelectOption(pe.getLabel(), pe.getLabel()));
            }
        }
        return oppStages;
    }
    
     public List<SelectOption> getRTypes() {
        if(RTypes == null){
            RTypes = new List<SelectOption>();
            RTypes.add(new SelectOption(' ','- none -'));
            RTypes.addAll(RecordTypes.getStringRecordTypesForSelectList('Opportunity'));
        }
        return RTypes;
    }
    
    public List<SelectOption> getTypes() {
        if(Types == null){
            Types = new List<SelectOption>();
            Types.add(new SelectOption(' ','- none -'));
            Schema.DescribeFieldResult F = Schema.sObjectType.Opportunity.fields.Type; 
            List<Schema.PicklistEntry> P = F.getPicklistValues();
        
            for (Schema.PicklistEntry plistentry: P) {
                Types.add(new SelectOption(plistentry.getLabel(),plistentry.getLabel()));
            }
            
        }
        return Types;
    }
    
    private void showMsg(String arg, ApexPages.Severity severity){
        ApexPages.Message myMsg = new ApexPages.Message(severity,arg);
        ApexPages.addMessage(myMsg);
    }
    
    public void updateSettings(){
        String s = '';
        for (String rt : acctRTs) {
            if (rt!=null&&rt!='')
            s += ';' + rt;
        }
        system.debug('s: ' + s);
        if (s != '') pageSettings.Excluded_Account_Opp_Rectypes__c = s.substring(1);
        
        s = '';
        for (String rt : contactRTs) {
            if (rt!=null&&rt!='')
            s += ';' + rt;
        }
        if (s != '') pageSettings.Excluded_Contact_Opp_Rectypes__c = s.substring(1);
        
        
        s = '';
        for (String tp : acctTypes) {
            if (tp!=null&&tp!='')
            s += ';' + tp;
        }
        if (s != '') pageSettings.Excluded_Account_Opp_Types__c = s.substring(1);
        
        s = '';
        for (String tp : contactTypes) {
            if (tp!=null&&tp!='')
            s += ';' + tp;
        }
        if (s != '') pageSettings.Excluded_Contact_Opp_Types__c = s.substring(1);
        update pageSettings;
        showMsg('Households Settings updated',ApexPages.Severity.INFO);
        //schedule the rollup if need be
        scheduleRollups();
    }
    
    public void activateHouseholdNaming(){
    	runningBatch = true; 
    	    	
    	pageSettings.Advanced_Household_Naming__c = true;
    	update pageSettings;
    	
    	//call advanced rolup batch process
    	HouseholdNaming hn = new Householdnaming();
    	hn.ActivateAdvancedGreetings(false);
    	
    	/*
    	//refresh page
    	PageReference pr;// = new PageReference();
        pr.setRedirect(true);
        return pr;
    	*/
    	
    }
    
    public void checkForUpdates(){
        NPSPPkgVersionCheck npvc = new NPSPPkgVersionCheck('npo02');        
        npvc.NPSPCheckVersion(true);
    }
    
     public static testMethod void TEST_householdsSettings() {
        
        Test.setCurrentPageReference(new PageReference('Page.householdsSettings'));
        
        Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(new Households_Settings__c (Household_Rules__c = Households.ALL_INDIVIDUALS_PROCESSOR));
        
        //pass the controller into the extension
        householdsSettings controller = new householdsSettings(); 
        controller.getSettingsFirstTime();
        system.assertNotEquals(null,controller.getSettings());
        
        List<SelectOption> householdrules =  controller.gethouseholdrules(); 
        system.assertEquals(3,householdrules.size());
        
        List<SelectOption> oppStages = controller.getoppStages();
        system.assertNotEquals(null,oppStages);
        
        List<SelectOption> conRoles = controller.getcontactRoles();
        system.assertNotEquals(null,conRoles);
        
        List<SelectOption> opptypes = controller.getTypes();
        system.assertNotEquals(null,opptypes);
        
        List<SelectOption> oppRTypes = controller.getRTypes();
        system.assertNotEquals(null,oppRTypes);
        controller.acctRTs.add(RecordTypes.getRecordTypeNameForGiftsTests('Opportunity'));
        controller.contactRTs.add(RecordTypes.getRecordTypeNameForGiftsTests('Opportunity'));
        
        controller.acctTypes.add('In-Kind');
        controller.contactTypes.add('In-Kind');
        controller.pageSettings.Enable_Opp_Rollup_Triggers__c = true;
        controller.updateSettings();
                
    }
    /*
	static testMethod void testFirstRun()
    {
    	//get rid of settings
    	delete [select id from Households_Settings__c limit 100];
    	//get the default value
		String defaultValue;
        boolean aDefaultIsSelected = false;
        Schema.DescribeFieldResult F = Schema.sObjectType.Contact.fields.SystemHouseholdProcessor__c; 
        List<Schema.PicklistEntry> P = F.getPicklistValues();
        for(Schema.PicklistEntry pe : P){
            if (pe.isDefaultValue()){
                    defaultValue = pe.getValue();
                    break;
            }
        }
         Test.setCurrentPageReference(new PageReference('Page.contactSettings'));
        
        //pass the controller into the extension
        householdsSettings controller = new householdsSettings(); 
        controller.getSettingsFirstTime();
		if(defaultValue!=null){
			system.assertEquals(controller.pageSettings.Household_Rules__c,defaultValue);
		} else {
			system.assertEquals(controller.pageSettings.Household_Rules__c,Households.NO_HOUSEHOLDS_PROCESSOR);
		}

    }
    */
    
}