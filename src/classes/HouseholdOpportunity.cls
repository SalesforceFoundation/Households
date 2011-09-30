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
* @description Updates and managed opportunity contact roles for Household members, invoked via opp trigger 
*/
public class HouseholdOpportunity {
    public HouseholdOpportunity(){}    

    public HouseholdOpportunity(Opportunity[] opportunities, Opportunity[] oldOpportunities, Households.triggerAction ta)
    {
        npe01__Contacts_and_Orgs_Settings__c ContactsSettings = npe01.Constants.getContactsSettings();
        Households_Settings__c currentHouseholdsSettings = Households.getHouseholdsSettings();
        if(currentHouseholdsSettings.Household_Contact_Roles_On__c){
        //get all Opps in the trigger set that are for individual accounts 
        List<Opportunity> oppsForContactRoles = [select Id, AccountId, account.npe01__One2OneContact__c,account.npe01__SYSTEMIsIndividual__c from Opportunity where Id IN :opportunities AND account.npe01__SYSTEMIsIndividual__c = true];
        
        if(oppsForContactRoles.size()>0){
            
            //set of contact Ids on Accounts for Opps in the trigger set
            Set<Id> contactIds = new Set<Id>();         
            
            //real contacts queried from that list of Ids on the Accounts
            List<Contact> individualContacts = new List<Contact>();
            
            //list of contacts queried for households of contacts on the opps
            List<Contact> householdContacts = new List<Contact>();
            
            //map Contacts to Opps
            Map<id,List<Opportunity>> contactIdToOpps = new Map<id,List<Opportunity>>();
            
            //map Household Id to the member Contacts
            Map<id,List<Contact>> householdIdToContact = new Map<id,List<Contact>>();           
            
            //loop throught the Opportunities
            for(Opportunity thisOpp : oppsForContactRoles){ 
                //grab all the contacts off the Accounts
                contactIds.add(thisOpp.account.npe01__One2OneContact__c);
                //create the map of contacts to opps
                if(contactIdToOpps.get(thisOpp.account.npe01__One2OneContact__c)==null){
                    contactIdToOpps.put(thisOpp.account.npe01__One2OneContact__c,new List<Opportunity>());                  
                }
                contactIdToOpps.get(thisOpp.account.npe01__One2OneContact__c).add(thisOpp);
            }
            
            //map for contacts to their households because we can't get a query with Opp Id, Contact Id, and Household Id
            Map<Id,Id> contactIdToHouseholdId = new Map<Id,Id>();
            
            //query all contacts to get the Household Ids
            individualContacts = [select id,Household__c from Contact where Id IN :contactIds];
            
            //create a map of contacts and thier Household Ids
            for(Contact myContact : individualContacts){
                if(myContact.Household__c!=null){
                    contactIdToHouseholdId.put(myContact.Id,myContact.Household__c);        
                }       
            }
            
            //query all contacts in all the Households
            householdContacts = [select id,Household__c from Contact where Household__c IN :contactIdToHouseholdId.values()];
            
            //create a map of Household Id to list of member contacts
            for(Contact myContact : householdContacts){
                if(householdIdToContact.get(myContact.Household__c)==null){
                    householdIdToContact.put(myContact.Household__c,new List<Contact>());                   
                }
                householdIdToContact.get(myContact.Household__c).add(myContact);
            }
            
            map <String,Id> contactOppToContactRole = new Map <String,Id> ();
        
            // query for OppConRoles where primary=true and OppID in arg set
            OpportunityContactRole[] conRoles = [select Id,OpportunityId, ContactId From OpportunityContactRole WHERE IsPrimary = true AND Opportunity.Id IN :oppsForContactRoles ];
            String uniqueConRole = '';
            // now loop through the results and build the map
            for (OpportunityContactRole thisCR : conRoles) {
                uniqueConRole = string.valueOf(thisCR.OpportunityId) + string.valueOf(thisCR.ContactId);
                contactOppToContactRole.put(uniqueConRole , thisCR.Id );
            }
            
            //list to hold new contact roles
            List<OpportunityContactRole> contactRolesForCreation = new List<OpportunityContactRole>();
            List<OpportunityContactRole> contactRolesForUpdate = new List<OpportunityContactRole>();
            
            //loop through all contacts that have opps
            for(Id thisContactId : contactIdToOpps.keySet()){
                //loop through all opps
                for(Opportunity thisOpp : contactIdToOpps.get(thisContactId)) {
                    
                    if(contactIdToHouseholdId.get(thisContactId)!=null){
                        //loop through all households members
                        for(Contact householdMember : householdIdToContact.get(contactIdToHouseholdId.get(thisContactId))){
                            
                            //different role for primary donor
                            if(thisContactId==householdMember.Id){
                                uniqueConRole = string.valueOf(thisOpp.Id)+string.valueOf(householdMember.Id);
                                if(contactOppToContactRole.get(uniqueConRole)!=null){
                                    OpportunityContactRole thisRole = new OpportunityContactRole(id=contactOppToContactRole.get(uniqueConRole));
                                    thisRole.Role = ContactsSettings.npe01__Opportunity_Contact_Role_Default_role__c;
                                    contactRolesForUpdate.add(thisRole);
                                    
                                } else {
                                    OpportunityContactRole thisRole = new OpportunityContactRole();
                                    thisRole.OpportunityId = thisOpp.Id;
                                    thisRole.ContactId = householdMember.Id;
                                    thisRole.Role = ContactsSettings.npe01__Opportunity_Contact_Role_Default_role__c;
                                    thisRole.isPrimary = true;
                                    contactRolesForCreation.add(thisRole);
                                }
                            } else {
                                OpportunityContactRole thisRole = new OpportunityContactRole();
                                thisRole.OpportunityId = thisOpp.Id;
                                thisRole.ContactId = householdMember.Id;
                                thisRole.Role = currentHouseholdsSettings.Household_Member_Contact_Role__c;
                                contactRolesForCreation.add(thisRole);
                            }
                            
                        }
                    }                   
                }
            }
            If(contactrolesforCreation!=null){
                insert contactrolesforCreation;   
            }
            if(contactRolesForUpdate!=null){
                update contactRolesForUpdate;   
            }   
        }
    }
    }
}