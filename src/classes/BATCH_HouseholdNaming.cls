/*
    Copyright (c) 2009, Salesforce.com Foundation
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
* @date 2011 (2.3)
* @description Class provides a batchable wrapper for Household naming functionality. Generally called only on initial activation.
*/
global class BATCH_HouseholdNaming implements Database.Batchable<SObject> {
// batch apex class to name households in existing orgs
    
    public String query {get; set;}
    public boolean isActivation {get; set;} 
    
    /** @description constructor for the class */
    public BATCH_HouseholdNaming(string q, boolean isA) {    	   
    	isActivation = isA;    	
        query = q; 
    }
    /** @description default old constructor to skip activation sequence */    
    public BATCH_HouseholdNaming(string q) {
    	query = q;
    	isActivation = false;    	
    }    
    /** @description Start method of batch class */
    global database.Querylocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);      
    }
    /** @description The execution logic for the batch. Includes seperate paths for initial activations */
    global public void execute(Database.BatchableContext bc, Sobject[] result) {
        // run rollups for this batch  
        HouseholdProcessControl.inFutureContext = true;     
        
        //first, if this is coming from the VF settings interface, we need to markup
        //all of the houesholds that have existing names        
        if (isActivation){
        	
            //sort our contacts objects into a map of 
            //household id and list of contacts
            map<id, list<Contact>> hhIDContactMap = new map<id, list<Contact>>();
            //sort contacts by household
            for (sobject s : result){               
            	Contact c = (Contact)s; 
                if (!hhIDContactMap.containskey(c.npo02__Household__r.id))
                    hhidContactMap.put(c.npo02__Household__r.id, new list<Contact>{c});
                else{
                    list<Contact> clist = hhidContactMap.get(c.npo02__Household__r.id);
                    clist.add(c);
                }
            }
        
            //get the actual household objects being operating on so we can update them if needed
            map<id, npo02__Household__c> Householdsforupdate = new map<id, npo02__Household__c>([select id, npo02__SYSTEM_CUSTOM_NAMING__c, Name, npo02__Formal_Greeting__c, 
            npo02__Informal_Greeting__c from npo02__Household__c where id IN :hhidContactMap.keyset()]);
            
            list<npo02__Household__c> updatelist = new list<npo02__Household__c>();
        
            for (id hhid : hhidContactMap.keyset()){
            	boolean needsupdate = false;
            	
            	npo02__Household__c h = new npo02__Household__c();
            	h = Householdsforupdate.get(hhid);
                
                if (h.npo02__SYSTEM_CUSTOM_NAMING__c != null)
                    h.npo02__SYSTEM_CUSTOM_NAMING__c += ';';                              	         
                else
                    h.npo02__SYSTEM_CUSTOM_NAMING__c = '';                                      
                
                if(h.npo02__Formal_Greeting__c != null && !h.npo02__SYSTEM_CUSTOM_NAMING__c.contains('Formal_Greeting__c')){
                    h.npo02__SYSTEM_CUSTOM_NAMING__c += 'Formal_Greeting__c' + ';';
                    needsupdate = true;                  	
                }
                if (h.npo02__Informal_Greeting__c != null && !h.npo02__SYSTEM_CUSTOM_NAMING__c.contains('Informal_Greeting__c')){
                	h.npo02__SYSTEM_CUSTOM_NAMING__c += 'Informal_Greeting__c' + ';';
                	needsupdate = true;                	
                }    

                //pile up a list of all the lastnames in the household
                set<string> hhlastnames = new set<string>();
                for (Contact c : hhidcontactmap.get(hhid))
                    hhlastnames.add(c.LastName);	
                
                boolean hasnamematch = false;
                for (string s : hhlastnames){
                	if (h.Name == s + ' ' + system.label.DefaultHouseholdName)
                	   hasnamematch = true;                	
                }
                
                //if we never found a matching default name its been customized, so
                //add them to the update list and mark the custom naming field accordingly
                if (!hasnamematch){
                	if (!h.npo02__SYSTEM_CUSTOM_NAMING__c.contains('Name'))
                	   h.npo02__SYSTEM_CUSTOM_NAMING__c += 'Name' + ';';
                	
                	needsupdate = true;                	
                }
                
                if (needsupdate)
                    updatelist.add(h);                
            }
        
            if(updatelist.size() > 0)
                Database.Saveresult[] sr = database.update(updatelist, false);
        }

        //now run the regular process for completing the batch run                
        HouseholdNaming hn = new HouseholdNaming();
        set<id> hhids = new set<id>();
        for (sobject s : result){
            Contact c = (Contact)s;        
            hhids.add(c.npo02__household__r.id);
        }
        list<id> hhidlist = new list<id>();
        hhidlist.addall(hhids);
        
        hn.UpdateNames(hhidlist);
    }
    /** @description Finish method for the batchable class. */
    global void finish(Database.BatchableContext bc) {
    }
    /** @description Test method for batch */
    public static testMethod void testBatch() {
        
        Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
            new Households_Settings__c (
                Household_Rules__c = Households.ALL_PROCESSOR,
                Always_Rollup_to_Primary_Contact__c = true,
                Enable_Opp_Rollup_Triggers__c = true,
                Excluded_Account_Opp_Rectypes__c = null,
                Excluded_Account_Opp_Types__c = null,
                Excluded_Contact_Opp_Rectypes__c = null,
                Excluded_Contact_Opp_Types__c = null,
                Membership_Record_Types__c = null,
                Advanced_Household_Naming__c = true
            ));
            
        npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
           npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
           npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
           npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
        ));
            
                
        // create & insert contact(s)
        Contact[] TestCons = new contact[]{ new contact(
            FirstName= npe01.Constants.CONTACT_FIRSTNAME_FOR_TESTS,
            LastName= npe01.Constants.CONTACT_LASTNAME_FOR_TESTS,
            npe01__Private__c=false,
            npe01__WorkEmail__c = npe01.Constants.CONTACT_EMAIL_FOR_TESTS, 
            npe01__Preferred_Email__c = npe01.Constants.CONTACT_PREFERRED_EMAIL_FOR_TESTS,
            npe01__WorkPhone__c = npe01.Constants.CONTACT_PHONE_FOR_TESTS,
            npe01__PreferredPhone__c = npe01.Constants.CONTACT_PREFERRED_PHONE_FOR_TESTS
        ) };
        insert TestCons;
            
        //get the household to be updated
        id hhid = [select Household__r.id from Contact where id = :testcons[0].id].id;                        
        system.debug('ID IS=================='+ hhid);    
        
        BATCH_HouseholdNaming batch = new BATCH_HouseholdNaming(
        'select household__r.id from Contact where household__r.id = \'' + hhid + '\' limit 200', true
        );
            
        Test.StartTest(); 
            id batchProcessId = database.executeBatch(batch);
        Test.StopTest();
    }
}