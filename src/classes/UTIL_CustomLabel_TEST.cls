/*
    Copyright (c) 2017, Salesforce.org
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
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
@isTest
private with sharing class UTIL_CustomLabel_TEST {
    
    //we have some packaged labels that we no longer reference by the underlying package.
    //unfortunately, this causes our local DE Orgs to not include them in our local package.
    //so we now refer to them here, just so our DE Orgs will keep the in our local package.
    private static testmethod void keepPackagedLabelsInPackage() {
        string str;
        str = Label.Add;
        str = Label.AddAndMerge;
        str = Label.AddAndRemove;
        str = Label.AddHouseholdMembers;
        str = Label.AddressCopyFailure;
        str = Label.AddressCopySuccess;
        str = Label.AddressCopyUnknownObject;
        str = Label.AddressToAllMembers;
        str = Label.AlreadyInHousehold;
        str = Label.AutoFormalGreeting;
        str = Label.AutoInformalGreeting;
        str = Label.AutoName;
        str = Label.Change;
        str = Label.ChangeAddress;
        str = Label.ChangesNotSaved;
        str = Label.ContactAlreadyInHousehold;
        str = Label.ContactLastNameRqd;
        str = Label.ContactNameRqd;
        str = Label.CreatedOnSave;
        str = Label.DefaultHouseholdName;
        str = Label.DefaultHouseholdTransactionCurrency;
        str = Label.Delete;
        str = Label.EnterNewAddress;
        str = Label.ExcludeText;
        str = Label.ExistingHousehold;
        str = Label.FindContactByName;
        str = Label.HouseholdAddress;
        str = Label.HouseholdAnonymousGreeting;
        str = Label.HouseholdAnonymousName;
        str = Label.HouseholdDetails;
        str = Label.HouseholdMembers;
        str = Label.HouseholdNameConnector;
        str = Label.HouseholdNameOverrun;
        str = Label.Household_Contact_Roles_Help_Text;
        str = Label.Household_Contact_Role_Processor_Off;
        str = Label.Household_Contact_Role_Processor_On;
        str = Label.Household_Member_Contact_Role;
        str = Label.Household_Rules_Help_Text;
        str = Label.ManageHousehold;
        str = Label.NameReplacementText;
        str = Label.NewContact;
        str = Label.NoContacts;
        str = Label.Opportunity_Error_Help_Text;
        str = Label.Opportunity_Rollup_Future_Call_Limit;
        str = Label.Opportunity_Rollup_Scheduling_Error_Text;
        str = Label.Primary_Donor_Contact_Role;
        str = Label.RollupErrorMessage;
        str = Label.SelectExistingAddress;
        str = Label.SetAddress;
        str = Label.UDRDescription;
    }
}