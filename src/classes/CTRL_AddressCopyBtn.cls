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
* @date 2011 (2.3)
* @description The controller for the VF page invoked by using the address copy button 
*/
public with sharing class CTRL_AddressCopyBtn {
	
	//simple utility for transferring a contact address to a household    
    //or pushing a household address out to its member contacts  
	private sobject obj;
	public string resulttext{get; set;}
	public string returnurl{get; set;}	
	
	//we redirect on success, hold on page for errors
	private boolean redirectPage = true;
    
    public CTRL_AddressCopyBtn(ApexPages.StandardController Controller){
    	    
            obj = (sobject)Controller.getRecord();
            PageReference pageRef = new PageReference('/' + obj.id);
            returnurl = pageref.getUrl();
    }
    
    public PageReference buttonClick(){
        
        if(obj instanceof Contact){
        	Contact c = (Contact)obj;
        	Household__c h;
        	
            //there must be a more efficient way to do this,
            //but for now, this will work
            c = [select Id, Household__c, Household__r.MailingStreet__c, Household__r.MailingCity__c, Household__r.MailingState__c, Household__r.MailingPostalCode__c, 
            Household__r.MailingCountry__c,             
            MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry From Contact where id = :c.id]; 
            
            if (c.Household__c != null){
            	
            	//get a reference to the HH object for updating
            	h = new Household__c(id = c.Household__r.id);
            	
            	Note n;
            	
            	//if there's a street already listed on the household
            	//save the old address as a note on the household object            	
            	if (c.Household__r.MailingStreet__c != null){
                    string notebody = '';
                    notebody += c.Household__r.MailingStreet__c + '  ';
                    notebody += c.Household__r.MailingCity__c + '  '; 
                    notebody += c.Household__r.MailingState__c + '  ';
                    notebody += c.Household__r.MailingPostalCode__c + '  ';
                    notebody += c.Household__r.MailingCountry__c;
            		n = new Note(Title = 'ADDRESS UPDATE FROM CONTACT: ' + system.today() + ' BY: ' + UserInfo.getName(), ParentId = h.id, Body = notebody);
            	}
            	
                h.MailingStreet__c = c.MailingStreet;
                h.MailingState__c = c.MailingState;
                h.MailingPostalCode__c = c.MailingPostalCode;
                h.MailingCity__c = c.MailingCity;
                h.MailingCountry__c = c.MailingCountry; 
            
                Database.Saveresult sr = Database.update(h, false);
                
                if (sr.isSuccess()){
                    resulttext = system.label.AddressCopySuccess;
                    if (n != null) insert n;
                    redirectPage = true;                    
                }
                else{
                	Database.Error[] ers= sr.getErrors();
                    resulttext = system.label.AddressCopyFailure + ': ' + ers[0].getStatusCode();
                    redirectPage = false;
                    showMsg(resulttext, ApexPages.Severity.ERROR);
                }            
            }
            else{
                resulttext = system.label.AddressCopyFailure + ': ' + 'NULL HOUSEHOLD';
                redirectPage = false;
                showMsg(resulttext, ApexPages.Severity.ERROR);
            }
        }
        
        //its coming from a household record, so push address to other members
        else if (obj instanceof Household__c){
        	
        	Household__c house = (Household__c)obj;
            list<Contact> constoupdate = new list<Contact>();
                        
            //we want these seperate in case a contact update fails - since we don't 
            //want to add a note for those
            map<id, Note> oldaddressnotes = new map<id, Note>();
            list<Note> notestoinsert = new list<Note>();
            house = [select MailingStreet__c, MailingState__c, MailingPostalCode__c, MailingCity__c, MailingCountry__c from Household__c where id = :house.id];
            constoupdate = [select id, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry from Contact where Household__c = :house.id];
        
            for(Contact con : constoupdate){
                
                Note n;
                if (con.MailingStreet != null){
                	string notebody = '';
                    notebody += con.MailingStreet + '  ';
                    notebody += con.MailingCity + '  '; 
                    notebody += con.MailingState + '  ';
                    notebody += con.MailingPostalCode + '  ';
                    notebody += con.MailingCountry;
                    n = new Note(Title = 'ADDRESS UPDATE FROM HOUSEHOLD: ' + system.today() + ' BY: ' + UserInfo.getName(), ParentId = con.id, Body = notebody);
                	notestoinsert.add(n);
                }	
            	
            	con.MailingStreet = house.MailingStreet__c;
            	con.MailingState = house.MailingState__c;
            	con.MailingPostalCode = house.MailingPostalCode__c;
            	con.MailingCity = house.MailingCity__c;
            	con.MailingCountry = house.MailingCountry__c;
            }
    
            try{
            	update constoupdate;   
            	insert notestoinsert;
            	redirectPage = true;         	
            }
            
            catch(Exception e){
                resulttext = system.label.AddressCopyFailure + ': ' + e.getMessage();
                redirectPage = false;
                showMsg(resulttext, ApexPages.Severity.ERROR);            	
            }   
        }
        
        //unknown object
        else{
        	resulttext = system.label.AddressCopyUnknownObject;
        	redirectPage = false;
        	showMsg(resulttext, ApexPages.Severity.ERROR);
        }
        
        //decide how to handle the redirect
        if (redirectPage){
        	PageReference pageRef = new PageReference('/' + obj.id);
            pageRef.setRedirect(true);
            return pageRef;
        }        
        else{
        	return null;
        }
    }
    
    private void showMsg(String arg, ApexPages.Severity severity){
        ApexPages.Message myMsg = new ApexPages.Message(severity,arg);
        ApexPages.addMessage(myMsg);
    }    
        
    public static testMethod void TEST_AddressUtility(){
    	
    	Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.NO_HOUSEHOLDS_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
    	
        
        Household__c hh = new Household__c(
           MailingStreet__c = '123 Main St.',
           MailingState__c = 'PA',
           MailingPostalCode__c = '18940',
           MailingCity__c = 'Newtown',
           MailingCountry__c = 'USA'
        );
        
        insert hh;
        
        Contact cc = new Contact(
           Household__c = hh.id,
           LastName = 'TestLName',
           MailingStreet = '1 Oak Lane',
           MailingState = 'WA',
           MailingPostalCode = '98122',
           MailingCity = 'Seattle',
           MailingCountry = 'CAN'
        );
        
        insert cc;
        
        // instantiate the controller w/ the contact
        ApexPages.StandardController scc = new ApexPages.StandardController(cc);
        CTRL_AddressCopyBtn cacbc = new CTRL_AddressCopyBtn(scc);
        PageReference prc = cacbc.buttonClick();
        system.assert(prc.getUrl().contains(cc.id));
        Household__c h = [select id, MailingStreet__c, MailingState__c, MailingPostalCode__c, MailingCity__c, MailingCountry__c from Household__c where id = :hh.id];
        system.assertEquals(h.MailingStreet__c, cc.MailingStreet);
        system.assertEquals(1, [select count() from Note where ParentID = :h.id]);
        
        //modify our household to a diff address
        hh.MailingStreet__c = '8675 ThreeOhNine Lane';
        update hh;
        
        //instantiate the controller wiht the new hh address
        scc = new ApexPages.StandardController(hh);
        cacbc = new CTRL_AddressCopyBTN(scc);
        prc = cacbc.buttonClick();
        system.assert(prc.getUrl().contains(hh.id));
        Contact c1 = [select id, MailingStreet from Contact where Household__c = :hh.id]; 
        system.assertEquals(hh.MailingStreet__c, c1.MailingStreet);
        system.assertEquals(1, [select count() from Note where ParentID = :c1.id]);
                
        /*test error conditions*/
        
        //unsupported object test
        Account a = new Account(Name = 'TESTACCOUNT');
        insert a;        
        scc = new ApexPages.StandardController(a);
        cacbc = new CTRL_AddressCopyBTN(scc);
        prc = cacbc.buttonClick();
        system.assert(prc == null);
        
        //contact w/o HH
        Contact c = new Contact(Lastname = 'NullHH');
        insert c;
        scc = new ApexPages.Standardcontroller(c);
        cacbc = new CTRL_AddressCopyBTN(scc);
        prc = cacbc.buttonClick();
        system.assert(prc == null);
    }
}