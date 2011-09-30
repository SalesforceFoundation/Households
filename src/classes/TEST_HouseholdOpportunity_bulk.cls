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
* @date 2011 (1.x)
* @description This class contains unit tests for validating the behavior of Apex classes and triggers. 
*/

@isTest
private class TEST_HouseholdOpportunity_bulk {

      /// <name> newIndContactAllContactsProcessor </name>
    /// <summary> test insert individual with all contacts processor </summary>
    static testMethod void newOpps() {
    	
    	Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(new Households_Settings__c (Household_Rules__c = Households.ALL_PROCESSOR));
        
        npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR));
                
        String street = '2345 Elm St.';
        String city = 'Seattle';
        String state = 'WA';
        String zip = '88777';
        String country = 'US';
        String lastname = 'SmithForTest99';
        
        List<Contact> cons = new List<contact>();
        Integer conCount = 200;
        for(Integer i=0;i<conCount;i++){
            Contact con = new Contact(
                FirstName='test',
                LastName=lastname,
                MailingStreet = street,
                MailingCity = city,
                MailingState = state,
                MailingPostalCode = zip,
                MailingCountry = country,
                SystemHouseholdProcessor__c = 'All New or Edited Contacts'
            );
            cons.add(con);
        }
        
        insert cons;
        Contact[] createdContacts = [select AccountId,Household__c,
        Household__r.MailingStreet__c, Household__r.MailingCity__c,
        Household__r.MailingState__c, Household__r.MailingPostalCode__c,
        Household__r.MailingCountry__c, Household__r.Name from Contact where id IN :cons];
        
        List<Opportunity> opps = new List<Opportunity>();
        
        for(Contact myContact : createdContacts){
            Opportunity opp = new Opportunity(
                Name='opp1',
                closeDate=System.today(),
                StageName='closed won',
                AccountId= myContact.AccountId
            );
            opps.add(opp);
        }
        
        Id firstHouseholdId = createdContacts[0].Household__c;
        system.assertEquals(street,createdContacts[0].Household__r.MailingStreet__c);
        system.assertEquals(city,createdContacts[0].Household__r.MailingCity__c);
        system.assertEquals(state,createdContacts[0].Household__r.MailingState__c);
        system.assertEquals(zip,createdContacts[0].Household__r.MailingPostalCode__c);
        system.assertEquals(country,createdContacts[0].Household__r.MailingCountry__c);
        system.assertEquals(lastname + ' Household',createdContacts[0].Household__r.Name);
        Test.startTest();
        //blank out the HH
        for(Contact thisContact : createdContacts){
            thisContact.Household__c = null;
        }
        update createdContacts;
        Test.stopTest();
        createdContacts = [select Household__r.Name,Household__r.MailingStreet__c,Household__r.MailingCity__c,Household__r.MailingState__c,Household__r.MailingPostalCode__c,Household__r.MailingCountry__c,Household__c from Contact where id IN :cons];
        
        system.assertNotEquals(firstHouseholdId,createdContacts[0].Household__c);
        system.assertEquals(street,createdContacts[0].Household__r.MailingStreet__c);
        system.assertEquals(city,createdContacts[0].Household__r.MailingCity__c);
        system.assertEquals(state,createdContacts[0].Household__r.MailingState__c);
        system.assertEquals(zip,createdContacts[0].Household__r.MailingPostalCode__c);
        system.assertEquals(country,createdContacts[0].Household__r.MailingCountry__c);
        system.assertEquals(lastname + ' Household',createdContacts[0].Household__r.Name);
    }
}