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
* @description Resposible for rollups of all opportunities to the requisite Account/Household/Contact 
*/
global virtual class OpportunityRollups {
 
    // settings
    boolean triggerRollupEnabled = true;
    boolean alwaysRollupToPrimaryContact = false;     
    boolean useFiscalYear = false;
    set<id> recordTypesToExcludeAccts = new set<id>();
    set<id> recordTypesToExcludeCons = new set<id>();
    set<id> mbrRecordTypes = new set<id>(); 
    set<string> oppTypesToExcludeAccts = new set<string>();
    set<string> oppTypesToExcludeCons = new set<string>();  
    //Modifiable ndays setting for 2.1    
    string ndayrollup = '365';  //default to original 365 day value
        
    //user defined rollups in list settings
    public static map<string, User_Rollup_Field_Settings__c> userRollups = new map<string, User_Rollup_Field_Settings__c>();
    public boolean hasContactRollups;
    public boolean hasHouseholdRollups;
    public boolean hasAccountRollups;
    
    static boolean recordTypesOnOpps; 
    
    //multi-currency vars
    static boolean multiCurrency;
    static SObjectField cfOppty;
    static SObjectField cfAccount;
    static SObjectField cfHousehold;
    static SObjectField cfContact;
    //exchangerate store
    static map<string, decimal> exchangeRates = new map<string,decimal>();
    //corporate currency
    static string currCorporate;  
    
    
    //determines if record types are enabled on opportunities 
    public static boolean areRecordTypesOnOpps(){
        if (recordTypesOnOpps==null){
            String giftRt = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
            if (giftRt!=null&&giftRt!=''){
                recordTypesOnOpps = true;
            } else {
                recordTypesOnOpps = false;  
            }
        }
        return recordTypesOnOpps;
    }

    static boolean isTest = false; 

    // constructor
    public OpportunityRollups() {

        // load settings
        Households_Settings__c rollupSettings = Households.getHouseholdsSettings();

        if (rollupSettings != null) {
            if (rollupSettings.Excluded_Contact_Opp_Rectypes__c != null) {
                set<string> rtNamesToExclude = new set<string>(rollupSettings.Excluded_Contact_Opp_Rectypes__c.split(';'));
                recordTypesToExcludeCons = RecordTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
            }
            if (rollupSettings.Excluded_Account_Opp_Rectypes__c != null) {
                set<string> rtNamesToExclude = new set<string>(rollupSettings.Excluded_Account_Opp_Rectypes__c.split(';'));
                recordTypesToExcludeAccts = RecordTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
            }
            if (rollupSettings.Excluded_Contact_Opp_Types__c != null) {
                oppTypesToExcludeCons = new set<string>(rollupSettings.Excluded_Contact_Opp_Types__c.split(';'));
            }
            if (rollupSettings.Excluded_Account_Opp_Types__c != null) {
                oppTypesToExcludeAccts = new set<string>(rollupSettings.Excluded_Account_Opp_Types__c.split(';'));
            }
            if (rollupSettings.Rollup_N_Day_Value__c != null){
                ndayRollup = string.valueOf(rollupSettings.Rollup_N_Day_Value__c.intValue()); 
            }
            if (rollupSettings.Membership_Record_Types__c != null) {
                set<string> mbrRecordTypeNames = new set<string>(rollupSettings.Membership_Record_Types__c.split(';'));
                mbrRecordTypes = RecordTypes.GetRecordTypeIdSet('Opportunity', mbrRecordTypeNames);
            }
            if (rollupSettings.Enable_Opp_Rollup_Triggers__c == false && !isTest)
                triggerRollupEnabled = false;
            
            if (rollupSettings.Always_Rollup_to_Primary_Contact__c == true)
                alwaysRollupToPrimaryContact = true;  
        
            //check the settings, if they have the fiscal year set
            //we still need to query to make sure its not a custom fiscal year
            //or else we'll throw errors when calling Fiscal_Year in queries
            if (rollupSettings.npo02__Use_Fiscal_Year_for_Rollups__c == true){
                integer hasCustomFYRecord = [select count() from FiscalYearSettings];
                
                //if org has customFY records, disable FY settings
                if (hasCustomFYRecord > 0)
                   useFiscalYear = false;
                else
                   useFiscalYear = true;
            }
        
        }
        
        //load user rollup settings - if they exist        
        userRollups = User_Rollup_Field_Settings__c.getAll().clone(); 
        
        //setup our object bools to demarcate which objects have user defined rollups
        //this will save us some cycles later on
        //also check runtime field validity
        hasContactRollups = false;
        hasHouseholdRollups = false;
        hasAccountRollups = false;              
        
        for (string s : userRollups.keySet()){
            User_Rollup_Field_Settings__c urfs = userRollups.get(s);
            if (urfs.Object_Name__c == 'Contact'){hasContactRollups = true;}        
            else if (urfs.Object_Name__c == 'Account'){hasAccountRollups = true;}
            else if (urfs.Object_Name__c == 'Household__c' || urfs.Object_Name__c == 'npo02__Household__c'){hasHouseholdRollups = true;}
        
            SobjectField targetField;
            SobjectField sourceField;
            
            set<string> SourceFieldNames = new set<string>();
            //check source field
            sourceField = Schema.sObjectType.Opportunity.fields.getMap().get(urfs.Source_Field__c);
            
            if (sourceField == null || SourceFieldNames.contains(urfs.Source_Field__c)) userRollups.remove(s);            
            SourceFieldNames.add(urfs.Source_Field__c);
                      
            //check target fields            
            if (urfs.Object_Name__c == 'Contact'){
                targetField = Schema.sObjectType.Contact.fields.getMap().get(urfs.Target_Field__c); 
                if (targetField == null) userRollups.remove(s);
            }
            else if (urfs.Object_Name__c == 'Account'){
                targetField = Schema.sObjectType.Account.fields.getMap().get(urfs.Target_Field__c); 
                if (targetField == null) userRollups.remove(s);               
            }
            else if (urfs.Object_Name__c == 'Household__c' || urfs.Object_Name__c == 'npo02__Household__c'){
                targetField = Schema.sObjectType.Household__c.fields.getMap().get(urfs.Target_Field__c); 
                if (targetField == null) userRollups.remove(s);
            }
        }       
    }           

    public void rollupAccount( id aid ) {
    // roll up a single account's opps
        
/*        map<id, account> amap = new map<id, account>(
            [select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastNDays__c, 
                npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c,
                npo02__OppsClosedThisYear__c,npo02__OppsClosedLastYear__c, npo02__OppsClosedLastNDays__c,
                npo02__OppsClosed2YearsAgo__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c                           
                from account where id = : aid AND npo02__NumberOfClosedOpps__c < 3000]);
*/
        // switch to dynamic SOQL for multicurrency
        map<id, account> amap = new map<id, account>((List<Account>)Database.query('select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastNDays__c,'+ 
                'npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c,'+
                'npo02__OppsClosedThisYear__c,npo02__OppsClosedLastYear__c, npo02__OppsClosedLastNDays__c,'+
                'npo02__OppsClosed2YearsAgo__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c '+
                (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+             
                'from account where id = :aid AND npo02__NumberOfClosedOpps__c < 3000'));
      
        if (!amap.isEmpty()) 
            rollupAccounts( amap );
    }

    @future
    public static void rollupAccountsFuture( set<id> acctIds ) {
    // roll up a single account's opps
        
        if (acctIds != null && !acctIds.isEmpty()) { 
   /*         map<id, account> amap = new map<id, account>(
                [select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastNDays__c, 
                    npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c,
                    npo02__OppsClosedThisYear__c,npo02__OppsClosedLastYear__c, npo02__OppsClosedLastNDays__c,
                    npo02__OppsClosed2YearsAgo__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c  
                    from account where id in :acctIds AND npo02__NumberOfClosedOpps__c < 3000 ]); */
        // switch to dynamic SOQL for multicurrency
            map<id, account> amap = new map<id, account>((List<Account>) Database.query('select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastNDays__c, '+
                    'npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c,'+
                    'npo02__OppsClosedThisYear__c,npo02__OppsClosedLastYear__c, npo02__OppsClosedLastNDays__c,'+
                    'npo02__OppsClosed2YearsAgo__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c '+  
                    (isMultiCurrency() ? ', CurrencyIsoCode ' : '') +  
                    'from account where id in :acctIds AND npo02__NumberOfClosedOpps__c < 3000'));           
            
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupAccounts( amap );
        }
    }

    public void rollupAccounts( list<account> accts ) {
    // roll up opps for a set of accounts

        if (accts != null && !accts.isEmpty()) {
            rollupAccounts( new map<id, account>(accts) );
        }
    }

    public void rollupAccounts( map<id, account> amap ) {
    // roll up opps for a map of accounts
    // only accounts that have changed will get updated 

        //arg used by multi currency for rollup field currencies
        map<Id,Opportunity> opptyCurrencies;

        // copy the accounts to a map of zerod out versions
        map<id, account> accountsToUpdate = new map<id, account>();
        set<id> allAccts = amap.keyset();
        for (id aid : allAccts) {
            accountsToUpdate.put(aid, new Account(id = aid, npo02__TotalOppAmount__c = 0, npo02__AverageAmount__c = 0, 
                npo02__SmallestAmount__c = 0, npo02__LargestAmount__c = 0, npo02__FirstCloseDate__c = null,
                npo02__LastCloseDate__c = null, npo02__NumberOfClosedOpps__c = 0, npo02__OppAmountThisYear__c = 0, 
                npo02__OppsClosedThisYear__c = 0, npo02__OppAmountLastYear__c = 0, npo02__OppsClosedLastYear__c = 0,
                npo02__OppsClosed2YearsAgo__c = 0, npo02__OppAmount2YearsAgo__c = 0,
                npo02__OppsClosedLastNDays__c = 0, npo02__OppAmountLastNDays__c = 0, 
//              Membershipnpo02__OppsClosedThisYear__c = 0, Membershipnpo02__OppAmountLastYear__c = 0, Membershipnpo02__OppsClosedLastYear__c = 0,
//              Membershipnpo02__OppsClosed2YearsAgo__c = 0, Membershipnpo02__OppAmount2YearsAgo__c = 0, 
                npo02__TotalMembershipOppAmount__c = 0, npo02__NumberOfMembershipOpps__c = 0,               
                npo02__LastMembershipDate__c = null, npo02__LastMembershipAmount__c = 0,                
                npo02__LastMembershipLevel__c = null, npo02__LastMembershipOrigin__c = null,                
                npo02__MembershipJoinDate__c = null, npo02__MembershipEndDate__c = null,
                npo02__LastOppAmount__c = null                  
            ));
            
            // map currency across if multicurrency
            if(isMultiCurrency())
                accountsToUpdate.get(aid).put(cfAccount,amap.get(aid).get(cfAccount));
        }

        // copy all the rollups from each result row into the account objects
        integer startYear = system.today().year() - 2;
     
        String soqlStatement = '';
        if (useFiscalYear)
            soqlStatement += 'SELECT accountId, Fiscal_Year(CloseDate) CalendarYr, ';
        else
            soqlStatement += 'SELECT accountID, Calendar_Year(CloseDate) CalendarYr, ';
        
        soqlStatement += 'SUM(Amount) TotalOppAmount, AVG(Amount) AverageAmount, MIN(Amount) SmallestAmount, ';
        soqlStatement += 'MAX(Amount) LargestAmount, MIN(CloseDate) FirstCloseDate, MAX(CloseDate) LastCloseDate, ';
        for (string s : userRollups.keyset()){
            if (userRollups.get(s).Object_Name__c == 'Account'){
               User_Rollup_Field_Settings__c urfs = userRollups.get(s);
               soqlStatement += urfs.Field_Action__c + '(' + urfs.Source_Field__c + ') ' + urfs.Name + ', ';    
            }           
        }
        soqlStatement += 'COUNT_DISTINCT(Id) NumberOfClosedOpps, MAX(npo02__CombinedRollupFieldset__c) RollupFieldset '; 
        soqlStatement += 'FROM Opportunity ';
        soqlStatement += 'WHERE isWon=true '; 
        soqlStatement += 'AND (Amount != null) '; 
        if(areRecordTypesOnOpps()){
            soqlStatement += 'AND RecordTypeId NOT IN : recordTypesToExcludeAccts ';
        }
        soqlStatement += 'AND Type NOT IN : oppTypesToExcludeAccts ';
        soqlStatement += 'AND accountId IN : allAccts ';
        if (useFiscalYear){
            soqlStatement += 'GROUP BY ROLLUP (accountId, Fiscal_Year(closeDate)) ';
            soqlStatement += 'HAVING ( Fiscal_Year(closeDate) = null OR Fiscal_Year(closeDate) >= : startYear ) ';
        }
        else{
            soqlStatement += 'GROUP BY ROLLUP (accountId, Calendar_Year(closeDate)) ';
            soqlStatement += 'HAVING ( Calendar_Year(closeDate) = null OR Calendar_Year(closeDate) >= : startYear ) ';
        }
        soqlStatement += 'AND accountId != null';
        
        list<sobject> objectList = Database.query(soqlStatement);

        // invokes code to get the currency of npo02__CombinedRollupFieldset__c oppty
        opptyCurrencies = (isMultiCurrency() ? rcfFindCurrency(objectList) : null);
        
        for (sobject r : objectList){
                    
            //system.debug(Logginglevel.WARN, 'ROLLUP ROW: ' + r);

            // get the account id for this result row
            id aid = (id)(r.get('accountId'));
    
            // copy all the rollups from this result row into the account object    
            updateRollupFromResult((sobject)(accountsToUpdate.get(aid)), r, opptyCurrencies);
        }

        // also do rollups for last N days
        soqlStatement = 'SELECT accountId, '; 
        soqlStatement += 'SUM(Amount) TotalOppAmount, COUNT_DISTINCT(Id) NumberOfClosedOpps '; 
        soqlStatement += 'FROM Opportunity  '; 
        soqlStatement += 'WHERE isWon=true  '; 
        soqlStatement += 'AND (Amount != null) '; 
        if(areRecordTypesOnOpps()){ 
            soqlStatement += 'AND RecordTypeId NOT IN : recordTypesToExcludeAccts '; 
        }
        soqlStatement += 'AND Type NOT IN : oppTypesToExcludeAccts '; 
        soqlStatement += 'AND accountId IN : allAccts '; 
        soqlStatement += 'AND closeDate >= LAST_N_DAYS:' + ndayrollup + ' '; 
        soqlStatement += 'GROUP BY accountId '; 
        soqlStatement += 'HAVING accountId != null';
        
        objectList.clear();
        objectList = database.query(soqlStatement);
        
        
        
        for (sobject r : objectList ) {
            //system.debug(Logginglevel.WARN, 'ROLLUP ROW: ' + r);
            
            // get the ids
            id aid = (id)(r.get('accountId'));
                
            // process the result row, copying it into the contact record(s)
            updateRollupFromResultLastNDays((sobject)(accountsToUpdate.get(aid)), r);
        }

        if (!mbrRecordTypes.isEmpty()) {
            // also roll up memberships
            // uncomment if you are doing annual membership totals
            soqlStatement = 'SELECT accountId, ';
                    //Calendar_Year(CloseDate) CalendarYr, SUM(Opportunity.Total_Unpaid__c) TotalUnpaid,
            soqlStatement += 'SUM(Amount) TotalOppAmount, '; 
                    //SUM(Total_Unpaid__c) TotalUnpaid, MAX(Amount) LargestAmount, 
                    //AVG(Amount) AverageAmount, MIN(Amount) SmallestAmount,
            soqlStatement += 'MAX(CloseDate) LastCloseDate, ';
            soqlStatement += 'MIN(npe01__membership_start_date__c) FirstStartDate, MAX(npe01__membership_end_date__c) LastEndDate,  ';
            soqlStatement += 'COUNT_DISTINCT(Id) NumberOfClosedOpps, MAX(npo02__CombinedRollupFieldset__c) RollupFieldset  ';
            soqlStatement += 'FROM Opportunity ';
            soqlStatement += 'WHERE isWon=true  ';
            soqlStatement += 'AND (Amount != null)  ';
            if(areRecordTypesOnOpps()){
                soqlStatement += 'AND RecordTypeId IN : mbrRecordTypes ';
            }
            soqlStatement += 'AND Type NOT IN : oppTypesToExcludeAccts ';
            soqlStatement += 'AND accountId IN : allAccts ';
            
            if (useFiscalYear)
                soqlStatement += 'GROUP BY ROLLUP (accountId, Fiscal_Year(closeDate)) ';
            else
                soqlStatement += 'GROUP BY ROLLUP (accountId, Calendar_Year(closeDate)) ';
            soqlStatement += 'HAVING  ';
                    // ( Calendar_Year(closeDate) = null OR Calendar_Year(closeDate) >= : startYear ) AND
            soqlStatement += 'accountId != null';
            
            objectList.clear();
            objectList = database.query(soqlStatement);        
            
            // invokes code to get the currency of npo02__CombinedRollupFieldset__c oppty
            opptyCurrencies = (isMultiCurrency() ? rcfFindCurrency(objectList) : null);
            
            for (sobject r : objectList ) {
                //system.debug('ROLLUP ROW: ' + r);
    
                // get the account id for this result row
                id aid = (id)(r.get('accountId'));
                
                // copy all the rollups from this result row into the account object  
                updateRollupFromResultMembership((sobject)(accountsToUpdate.get(aid)), r, opptyCurrencies);
            }
        }

        // remove any records that have not changed
        for (id aid : allAccts) {
            account a1 = amap.get(aid); 
            account a2 = accountsToUpdate.get(aid);
            
            if (a1.npo02__TotalOppAmount__c == a2.npo02__TotalOppAmount__c &&
                    a1.npo02__OppsClosedThisYear__c == a2.npo02__OppsClosedThisYear__c &&
                    a1.npo02__OppsClosedLastYear__c == a2.npo02__OppsClosedLastYear__c &&
                    a1.npo02__OppsClosedLastNDays__c == a2.npo02__OppsClosedLastNDays__c &&
                    a1.npo02__OppsClosed2YearsAgo__c == a2.npo02__OppsClosed2YearsAgo__c &&
                    a1.npo02__OppAmountLastYear__c == a2.npo02__OppAmountLastYear__c &&
                    a1.npo02__OppAmount2YearsAgo__c == a2.npo02__OppAmount2YearsAgo__c &&                      
                    a1.npo02__OppAmountThisYear__c == a2.npo02__OppAmountThisYear__c &&
                    a1.npo02__OppAmountLastNDays__c == a2.npo02__OppAmountLastNDays__c &&
                    a1.npo02__TotalMembershipOppAmount__c == a2.npo02__TotalMembershipOppAmount__c &&
                    a1.npo02__LastCloseDate__c == a2.npo02__LastCloseDate__c)
                accountsToUpdate.remove(aid);
        }
        
        // update all the accounts from this batch 
        update accountsToUpdate.values(); 
    }

    public void rollupContact( id cid ) {
        // roll up opps for one contact
 /*       list<contact> cc = [select id, npo02__household__c, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, 
                npo02__OppAmountLastNDays__c, npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c, 
                npo02__NumberOfClosedOpps__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, 
                npo02__LastOppAmount__c,  npo02__MembershipEndDate__c, npo02__Household__r.npo02__MembershipEndDate__c,
                npo02__MembershipJoinDate__c, npo02__Household__r.npo02__MembershipJoinDate__c,
                npo02__Household__r.npo02__OppsClosedThisYear__c, npo02__Household__r.npo02__OppsClosedLastYear__c, 
                npo02__Household__r.npo02__OppsClosedLastNDays__c, npo02__Household__r.npo02__OppsClosed2YearsAgo__c, 
                npo02__Household__r.npo02__OppAmountLastYear__c, npo02__Household__r.npo02__OppAmount2YearsAgo__c,
                npo02__household__r.npo02__TotalOppAmount__c, npo02__household__r.npo02__OppAmountThisYear__c, 
                npo02__household__r.npo02__OppAmountLastNDays__c, npo02__household__r.npo02__TotalMembershipOppAmount__c,
                npo02__household__r.npo02__LastCloseDate__c, npo02__household__r.npo02__NumberOfClosedOpps__c
                from contact where id = :cid ]; */
        // switch to dynamic SOQL for multicurrency
        list<contact> cc = Database.query('select id, npo02__household__c, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, '+
                'npo02__OppAmountLastNDays__c, npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c, '+
                'npo02__NumberOfClosedOpps__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, '+
                'npo02__LastOppAmount__c, npo02__MembershipEndDate__c, npo02__Household__r.npo02__MembershipEndDate__c, '+ 
                'npo02__MembershipJoinDate__c, npo02__Household__r.npo02__MembershipJoinDate__c, '+
                'npo02__household__r.npo02__OppsClosedThisYear__c, npo02__household__r.npo02__OppsClosedLastYear__c, '+
                'npo02__household__r.npo02__OppsClosedLastNDays__c, npo02__household__r.npo02__OppsClosed2YearsAgo__c, '+
                'npo02__household__r.npo02__OppAmountLastYear__c, npo02__household__r.npo02__OppAmount2YearsAgo__c,'+
                'npo02__household__r.npo02__TotalOppAmount__c, npo02__household__r.npo02__OppAmountThisYear__c, '+
                'npo02__household__r.npo02__OppAmountLastNDays__c, npo02__household__r.npo02__TotalMembershipOppAmount__c,'+
                'npo02__household__r.npo02__LastCloseDate__c, npo02__household__r.npo02__NumberOfClosedOpps__c '+
                (isMultiCurrency() ? ', CurrencyIsoCode , npo02__household__r.CurrencyIsoCode ' : '')+  
                'from contact where id = :cid ');     
    
        if (!cc.isEmpty()) { 
            map<id, npo02__household__c> hhmap = new map<id, npo02__household__c>();
            if (cc[0].npo02__household__c != null) 
                hhmap.put(cc[0].npo02__household__c, cc[0].npo02__household__r);
        
            rollupContacts( new map<id, contact>( cc ), hhmap );
        }
    }
    
    public void rollupHousehold( id hhid ) {
/*        // roll up opps for one household
        list<npo02__household__c> hhs = [select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, 
            npo02__OppAmountLastNDays__c, npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c, npo02__TotalMembershipOppAmount__c,
            npo02__OppsClosedThisYear__c, npo02__OppsClosedLastYear__c, 
            npo02__OppsClosedLastNDays__c, npo02__OppsClosed2YearsAgo__c,
            npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c,
            npo02__MembershipEndDate__c, npo02__MembershipJoinDate__c
            from npo02__household__c where id = :hhid ]; */
        // switch to dynamic SOQL for multicurrency
        list<npo02__household__c> hhs = Database.query('select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c,'+ 
            'npo02__OppAmountLastNDays__c, npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c, npo02__TotalMembershipOppAmount__c,'+
            'npo02__OppsClosedThisYear__c, npo02__OppsClosedLastYear__c,'+ 
            'npo02__OppsClosedLastNDays__c, npo02__OppsClosed2YearsAgo__c,'+
            'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, '+
            'npo02__MembershipEndDate__c, npo02__MembershipJoinDate__c ' +
            (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+  
            'from npo02__household__c where id = :hhid ');
        
        if (!hhs.isEmpty()) 
            rollupHouseholds( hhs );
    }   
    
    public void rollupHouseholds( list<npo02__household__c> hhs ) {
    // roll up opps for households

        if (hhs != null && !hhs.isEmpty()) {
            
            map<id, npo02__household__c> hhmap = new map<id, npo02__household__c>( hhs );
  
            // extract keyset from map, as dynamic SOQL only handles single level binds
            set<id> hhmapids =hhmap.keyset();       
            
            // get household contacts
                        
/*            map<id, contact> cmap = new map<id, contact>([select id, npo02__household__c, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, 
                npo02__OppAmountLastNDays__c, npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c, 
                npo02__NumberOfClosedOpps__c, npo02__MembershipEndDate__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipJoinDate__c,
                npo02__LastOppAmount__c from contact where npo02__household__c in :hhmap.keyset() ]); */            
            // switch to dynamic SOQL for multicurrency
            map<id, contact> cmap = new map<id, contact>((List<contact>) Database.query('select id, npo02__household__c, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c,'+  
                'npo02__OppAmountLastNDays__c, npo02__TotalMembershipOppAmount__c, npo02__LastCloseDate__c,'+  
                'npo02__NumberOfClosedOpps__c, npo02__MembershipEndDate__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipJoinDate__c, '+  
                (isMultiCurrency() ? 'CurrencyIsoCode,' : '')+
                'npo02__LastOppAmount__c from contact where npo02__household__c in :hhmapids '));
            
            // roll up totals
            rollupContacts( cmap, hhmap );
        }
    }
    
    @future
    public static void rollupHouseholdsFuture( set<id> modifiedContactOpps ) {  
        
        map<id, contact> cmap = new map<id, contact>();
        map<id, npo02__household__c> hhmap = new map<id, npo02__household__c>();
        
        // use the contact roles to find the contacts and households
            if (!modifiedContactOpps.isEmpty()) {
                
                for (OpportunityContactRole r : 
/*[SELECT contactId, contact.npo02__household__c,
                        contact.npo02__TotalOppAmount__c, contact.npo02__OppAmountThisYear__c, contact.npo02__OppAmountLastNDays__c, 
                        contact.npo02__LastCloseDate__c, contact.npo02__NumberOfClosedOpps__c, contact.npo02__TotalMembershipOppAmount__c,
                        contact.npo02__OppAmountLastYear__c, contact.npo02__OppAmount2YearsAgo__c, contact.npo02__LastOppAmount__c,          
                        contact.npo02__household__r.npo02__TotalOppAmount__c, contact.npo02__household__r.npo02__OppAmountThisYear__c, 
                        contact.npo02__household__r.npo02__OppAmountLastNDays__c, contact.npo02__household__r.npo02__TotalMembershipOppAmount__c, 
                        contact.npo02__household__r.npo02__LastCloseDate__c, contact.npo02__household__r.npo02__NumberOfClosedOpps__c,
                        contact.npo02__household__r.npo02__OppsClosedThisYear__c, contact.npo02__household__r.npo02__OppsClosedLastYear__c, 
                        contact.npo02__household__r.npo02__OppsClosedLastNDays__c, contact.npo02__household__r.npo02__OppsClosed2YearsAgo__c,
                        contact.npo02__household__r.npo02__OppAmountLastYear__c, contact.npo02__household__r.npo02__OppAmount2YearsAgo__c,
                        contact.npo02__MembershipEndDate__c, contact.npo02__household__r.npo02__MembershipEndDate__c,
                        contact.npo02__MembershipJoinDate__c, contact.npo02__household__r.npo02__MembershipJoinDate__c
                        FROM OpportunityContactRole WHERE Opportunity.Id In : modifiedContactOpps and isPrimary = true ALL ROWS ] ) { */
                            
                    Database.query('SELECT contactId, contact.npo02__household__c, '+
                        'contact.npo02__TotalOppAmount__c, contact.npo02__OppAmountThisYear__c, contact.npo02__OppAmountLastNDays__c, '+
                        'contact.npo02__LastCloseDate__c, contact.npo02__NumberOfClosedOpps__c, contact.npo02__TotalMembershipOppAmount__c, '+
                        'contact.npo02__OppAmountLastYear__c, contact.npo02__OppAmount2YearsAgo__c, contact.npo02__LastOppAmount__c, '+ 
                        'contact.npo02__household__r.npo02__TotalOppAmount__c, contact.npo02__household__r.npo02__OppAmountThisYear__c, '+
                        'contact.npo02__household__r.npo02__OppAmountLastNDays__c, contact.npo02__household__r.npo02__TotalMembershipOppAmount__c, '+ 
                        'contact.npo02__household__r.npo02__LastCloseDate__c, contact.npo02__household__r.npo02__NumberOfClosedOpps__c, '+
                        'contact.npo02__household__r.npo02__OppsClosedThisYear__c, contact.npo02__household__r.npo02__OppsClosedLastYear__c, '+ 
                        'contact.npo02__household__r.npo02__OppsClosedLastNDays__c, contact.npo02__household__r.npo02__OppsClosed2YearsAgo__c, '+
                        'contact.npo02__household__r.npo02__OppAmountLastYear__c, contact.npo02__household__r.npo02__OppAmount2YearsAgo__c, '+
                        'contact.npo02__MembershipEndDate__c, contact.npo02__household__r.npo02__MembershipEndDate__c, ' +  
                        'contact.npo02__MembershipJoinDate__c, contact.npo02__household__r.npo02__MembershipJoinDate__c ' + 
                        (isMultiCurrency() ? ', contact.CurrencyIsoCode, contact.npo02__household__r.CurrencyIsoCode ' : '') +
                        'FROM OpportunityContactRole WHERE Opportunity.Id In : modifiedContactOpps and isPrimary = true ALL ROWS ') ) {   
                    
                    cmap.put(r.contactId, r.contact);
                    if (r.contact.npo02__household__c != null) {
                        hhmap.put(r.contact.npo02__household__c, r.contact.npo02__household__r);
                    }
                }    
            } 
            
            // roll up totals
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupContacts( cmap, hhmap );
    }

    public void rollupContacts( map<id, contact> cmap, map<id, npo02__household__c> hhmap ) {
    // roll up opps for a list of contacts and their households

        set<id> conIds = cmap.keySet();
        set<id> hhIds = hhmap.keySet();
        
        //arg used by multi currency for rollup field currencies
        map<Id,Opportunity> opptyCurrencies;

        // copy the contacts and households to a map of zerod out versions
        map<id, contact> contactsToUpdate = new map<id, contact>();
        map<id, npo02__household__c> householdsToUpdate = new map<id, npo02__household__c>();
        for (id cid : conIds) {
            contactsToUpdate.put(cid, new Contact(id = cid, npo02__TotalOppAmount__c = 0, npo02__AverageAmount__c = 0, 
                npo02__SmallestAmount__c = 0, npo02__LargestAmount__c = 0, npo02__FirstCloseDate__c = null, 
                npo02__LastCloseDate__c = null, npo02__NumberOfClosedOpps__c = 0, npo02__OppAmountThisYear__c = 0, 
                npo02__OppsClosedThisYear__c = 0, npo02__OppAmountLastYear__c = 0, npo02__OppsClosedLastYear__c = 0,
                npo02__OppsClosed2YearsAgo__c = 0, npo02__OppAmount2YearsAgo__c = 0, 
                npo02__OppsClosedLastNDays__c = 0, npo02__OppAmountLastNDays__c = 0,
//              Membershipnpo02__OppsClosedThisYear__c = 0, Membershipnpo02__OppAmountLastYear__c = 0, Membershipnpo02__OppsClosedLastYear__c = 0,
//              Membershipnpo02__OppsClosed2YearsAgo__c = 0, Membershipnpo02__OppAmount2YearsAgo__c = 0, 
                npo02__TotalMembershipOppAmount__c = 0, npo02__NumberOfMembershipOpps__c = 0,               
                npo02__LastMembershipDate__c = null, npo02__LastMembershipAmount__c = 0,                
                npo02__LastMembershipLevel__c = null, npo02__LastMembershipOrigin__c = null,                
                npo02__MembershipJoinDate__c = null, npo02__MembershipEndDate__c = null,                
                npo02__LastOppAmount__c = null
            ));
            
            // map currency across if multicurrency
            if(isMultiCurrency())
                contactsToUpdate.get(cid).put(cfContact,cmap.get(cid).get(cfContact));            
        }
        for (id hhid : hhIds) {
            householdsToUpdate.put(hhid, new npo02__household__c(id = hhid, npo02__TotalOppAmount__c = 0, npo02__AverageAmount__c = 0, 
                npo02__SmallestAmount__c = 0, npo02__LargestAmount__c = 0, npo02__FirstCloseDate__c = null, 
                npo02__LastCloseDate__c = null, npo02__NumberOfClosedOpps__c = 0, npo02__OppAmountThisYear__c = 0,
                npo02__OppsClosedThisYear__c = 0, npo02__OppAmountLastYear__c = 0, npo02__OppsClosedLastYear__c = 0,
                npo02__OppsClosed2YearsAgo__c = 0, npo02__OppAmount2YearsAgo__c = 0, 
                npo02__OppsClosedLastNDays__c = 0, npo02__OppAmountLastNDays__c = 0,
//              Membershipnpo02__OppsClosedThisYear__c = 0, Membershipnpo02__OppAmountLastYear__c = 0, Membershipnpo02__OppsClosedLastYear__c = 0,
//              Membershipnpo02__OppsClosed2YearsAgo__c = 0, Membershipnpo02__OppAmount2YearsAgo__c = 0, 
                npo02__TotalMembershipOppAmount__c = 0, npo02__NumberOfMembershipOpps__c = 0,               
                npo02__LastMembershipDate__c = null, npo02__LastMembershipAmount__c = 0,                
                npo02__LastMembershipLevel__c = null, npo02__LastMembershipOrigin__c = null,                
                npo02__MembershipJoinDate__c = null, npo02__MembershipEndDate__c = null,                
                npo02__LastOppAmount__c = null
            ));
        // map currency across if multicurrency
            if(isMultiCurrency())
                householdsToUpdate.get(hhid).put(cfHousehold,hhmap.get(hhid).get(cfHousehold));
        }

        // copy all the rollups from each result row into the contact objects
        integer startYear = system.today().year() - 2; 
        
        //generic object list for database query results
        //resolves aggregrate querymore issue
        list<sobject> objectList = new list<sobject>();
        
        if (alwaysRollupToPrimaryContact) {
            String soqlStatement = ''; 
            if (useFiscalYear)
                soqlStatement += 'SELECT contact.npo02__household__c hhid, contactId, Fiscal_Year(Opportunity.CloseDate) CalendarYr, ';
            else
                soqlStatement += 'SELECT contact.npo02__household__c hhid, contactId, Calendar_Year(Opportunity.CloseDate) CalendarYr, ';
            
            soqlStatement += 'SUM(Opportunity.Amount) TotalOppAmount,  ';
            soqlStatement += 'AVG(Opportunity.Amount) AverageAmount, MIN(Opportunity.Amount) SmallestAmount, ';
            soqlStatement += 'MAX(Opportunity.Amount) LargestAmount, MIN(Opportunity.CloseDate) FirstCloseDate, '; 
            soqlStatement += 'MAX(Opportunity.CloseDate) LastCloseDate, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps, ';
            for (string s : userRollups.keyset()){
                if (userRollups.get(s).Object_Name__c == 'Contact' || userRollups.get(s).Object_Name__c == 'Household__c' || userRollups.get(s).Object_Name__c == 'npo02__Household__c'){
                    User_Rollup_Field_Settings__c urfs = userRollups.get(s);
                    soqlStatement += urfs.Field_Action__c + '(Opportunity.' + urfs.Source_Field__c + ') ' + urfs.Name + ', ';    
                }           
            }            
            soqlStatement += 'MAX(Opportunity.npo02__CombinedRollupFieldset__c) RollupFieldset ';
            soqlStatement += 'FROM OpportunityContactRole  ';
            soqlStatement += 'WHERE isPrimary=true AND opportunity.isWon=true '; 
            soqlStatement += 'AND (Opportunity.Amount != null) '; 
            if(areRecordTypesOnOpps()){
                soqlStatement += 'AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons ';
            }
            soqlStatement += 'AND Opportunity.Type NOT IN : oppTypesToExcludeCons  ';
            soqlStatement += 'AND (contact.npo02__household__c IN : hhIds OR  ';
            soqlStatement += '(contact.npo02__household__c = null AND contactid IN :conids)) ';
            
            if (useFiscalYear)
                soqlStatement += 'GROUP BY CUBE(contact.npo02__household__c, contactId, Fiscal_Year(opportunity.closeDate)) ';
            else
                soqlStatement += 'GROUP BY CUBE(contact.npo02__household__c, contactId, Calendar_Year(opportunity.closeDate)) ';
            soqlStatement += 'HAVING (contactId IN : conIds OR contactId = null)';
           
             
            objectList = database.query(soqlStatement);
            
            // invokes code to get the currency of npo02__CombinedRollupFieldset__c oppty
            opptyCurrencies = (isMultiCurrency() ? rcfFindCurrency(objectList) : null);
            
            for (sobject r : objectList ) {
                
                // system.debug(Logginglevel.WARN, 'ROLLUP ROW: ' + r);
    
                // get the ids
                id cid = (id)(r.get('contactId'));
                id hhid = (id)(r.get('hhid'));
                    
                // process the result row, copying it into the contact record(s)
                // MS: we only want to fully calc the row if it is from the last few years - older years are only for calcing Best Year for contacts
                integer yr = (integer)r.get('CalendarYr');
                if (cid == null) { 
                    /*if (hhid != null && (yr >= startYear || yr==null) ) updateRollupFromResult((sobject)(householdsToUpdate.get(hhid)), r);*/
                    if (hhid != null && (yr >= startYear || yr==null) ) updateRollupFromResult((sobject)(householdsToUpdate.get(hhid)), r, opptyCurrencies);
                    // after doing regular processing, calc Best Contact Year stuff
                    // the rows are in year order, so just look start w/ the first yr, and increase as needed as we go
                    decimal yrAmt = (decimal)r.get('TotalOppAmount');
                    npo02__household__c HH = householdsToUpdate.get(hhid);
    
                } else {
                    // contact row
                    if ( yr >= startYear || yr==null) {
                        /*updateRollupFromResult((sobject)(contactsToUpdate.get(cid)), r);*/
                        updateRollupFromResult((sobject)(contactsToUpdate.get(cid)), r, opptyCurrencies);
                    }
                    // after doing regular processing, calc Best Contact Year stuff
                    // the rows are in year order, so just look start w/ the first yr, and increase as needed as we go
                    decimal yrAmt = (decimal)r.get('TotalOppAmount');
                    Contact con = contactsToUpdate.get(cid);
                }
            }
                
            // also do rollups for last N days
            soqlStatement = 'SELECT contact.npo02__household__c hhid, contactId, ';
            soqlStatement += 'SUM(Opportunity.Amount) TotalOppAmount, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps ';
            soqlStatement += 'FROM OpportunityContactRole  ';
            soqlStatement += 'WHERE isPrimary=true AND opportunity.isWon=true  ';
            soqlStatement += 'AND (Opportunity.Amount != null)  ';
            if(areRecordTypesOnOpps()){
                soqlStatement += 'AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons ';
            }
            soqlStatement += 'AND Opportunity.Type NOT IN : oppTypesToExcludeCons ';
            soqlStatement += 'AND (contact.npo02__household__c IN : hhIds OR  ';
            soqlStatement += '(contact.npo02__household__c = null AND contactid IN :conids)) ';
            soqlStatement += 'AND opportunity.closeDate >= LAST_N_DAYS:' + ndayrollup + ' ';
            soqlStatement += 'GROUP BY ROLLUP(contact.npo02__household__c, contactId) ';
            soqlStatement += 'HAVING (contactId IN : conIds OR contactId = null)  ';
            
            objectList.clear();
            objectList = database.query(soqlStatement);
            
            for (sobject r : objectList) {
    
                //system.debug(Logginglevel.WARN, 'ROLLUP ROW: ' + r);
                
                // get the ids
                id cid = (id)(r.get('contactId'));
                id hhid = (id)(r.get('hhid'));
                    
                // process the result row, copying it into the contact record(s)
                if (cid == null) { 
                    if (hhid != null)
                        updateRollupFromResultLastNDays((sobject)(householdsToUpdate.get(hhid)), r);
                } else {
                    // contact row  
                    updateRollupFromResultLastNDays((sobject)(contactsToUpdate.get(cid)), r);
                }
            }
    
            if (!mbrRecordTypes.isEmpty()) {
                // also do rollups for membership
                // if you need annual rollups for membership, uncomment the commented bits
                soqlStatement = 'SELECT contact.npo02__household__c hhid, contactId, ';                
                soqlStatement += 'SUM(Opportunity.Amount) TotalOppAmount,  ';
                soqlStatement += 'MAX(Opportunity.CloseDate) LastCloseDate,  ';
                soqlStatement += 'MIN(Opportunity.npe01__membership_start_date__c) FirstStartDate, '; 
                soqlStatement += 'MAX(Opportunity.npe01__Membership_End_Date__c) LastEndDate,  ';
                soqlStatement += 'MAX(contact.npo02__household__r.npo02__MembershipEndDate__c) HHMemberEndDate, ';
                soqlStatement += 'COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps, ';
                for (string s : userRollups.keyset()){
                    if (userRollups.get(s).Object_Name__c == 'Contact' || userRollups.get(s).Object_Name__c == 'Household__c' || userRollups.get(s).Object_Name__c == 'npo02__Household__c'){
                        User_Rollup_Field_Settings__c urfs = userRollups.get(s);
                        soqlStatement += urfs.Field_Action__c + '(Opportunity.' + urfs.Source_Field__c + ') ' + urfs.Name + ', ';    
                    }           
                } 
                soqlStatement += 'MAX(Opportunity.npo02__CombinedRollupFieldset__c) RollupFieldset ';
                soqlStatement += 'FROM OpportunityContactRole  ';
                soqlStatement += 'WHERE isPrimary=true AND opportunity.isWon=true '; 
                soqlStatement += 'AND (Opportunity.Amount != null) '; 
                if(areRecordTypesOnOpps()){
                    soqlStatement += 'AND Opportunity.RecordTypeId IN : mbrRecordTypes ';
                }
                soqlStatement += 'AND Opportunity.Type NOT IN : oppTypesToExcludeCons ';
                soqlStatement += 'AND (contact.npo02__household__c IN : hhIds OR  ';
                soqlStatement += '(contact.npo02__household__c = null AND contactid IN :conids)) ';
                soqlStatement += 'GROUP BY CUBE(contact.npo02__household__c, contactId) ';
                soqlStatement += 'HAVING (contactId IN : conIds OR contactId = null) '; 
                
                objectList.clear();
                objectList = database.query(soqlStatement);
                
                // invokes code to get the currency of npo02__CombinedRollupFieldset__c oppty
                opptyCurrencies = (isMultiCurrency() ? rcfFindCurrency(objectList) : null);
              
                for (sobject r : objectList) {
                            
                    // get the ids
                    id cid = (id)(r.get('contactId'));
                    id hhid = (id)(r.get('hhid'));
                        
                    // process the result row, copying it into the contact record(s)
                    if (cid == null) { 
                        if (hhid != null)
                            /*updateRollupFromResultMembership((sobject)(householdsToUpdate.get(hhid)), r);*/
                            updateRollupFromResultMembership((sobject)(householdsToUpdate.get(hhid)), r, opptyCurrencies);
                    } else {
                        // contact row  
                        /*updateRollupFromResultMembership((sobject)(contactsToUpdate.get(cid)), r);*/
                        updateRollupFromResultMembership((sobject)(contactsToUpdate.get(cid)), r, opptyCurrencies);
                    }
                }
            }
        } else {
            String soqlStatement = '';
            if (useFiscalYear)
                soqlStatement += 'SELECT contact.npo02__household__c hhid, contactId, Fiscal_Year(Opportunity.CloseDate) CalendarYr, ';
            else            
                soqlStatement += 'SELECT contact.npo02__household__c hhid, contactId, Calendar_Year(Opportunity.CloseDate) CalendarYr, ';
            soqlStatement += 'SUM(Opportunity.Amount) TotalOppAmount,  ';
            soqlStatement += 'AVG(Opportunity.Amount) AverageAmount, MIN(Opportunity.Amount) SmallestAmount, ';
            soqlStatement += 'MAX(Opportunity.Amount) LargestAmount, MIN(Opportunity.CloseDate) FirstCloseDate, '; 
            soqlStatement += 'MAX(Opportunity.CloseDate) LastCloseDate, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps, ';
            for (string s : userRollups.keyset()){
                if (userRollups.get(s).Object_Name__c == 'Contact' || userRollups.get(s).Object_Name__c == 'Household__c' || userRollups.get(s).Object_Name__c == 'npo02__Household__c'){
                    User_Rollup_Field_Settings__c urfs = userRollups.get(s);
                    soqlStatement += urfs.Field_Action__c + '(Opportunity.' + urfs.Source_Field__c + ') ' + urfs.Name + ', ';    
                }           
            } 
            soqlStatement += 'MAX(Opportunity.npo02__CombinedRollupFieldset__c) RollupFieldset ';
            soqlStatement += 'FROM OpportunityContactRole  ';
            soqlStatement += 'WHERE isPrimary=true AND opportunity.isWon=true '; 
            soqlStatement += 'AND (Opportunity.Amount != null) '; 
            if(areRecordTypesOnOpps()){
                soqlStatement += 'AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons ';
            }
            soqlStatement += 'AND Opportunity.Type NOT IN : oppTypesToExcludeCons ';
            soqlStatement += 'AND (opportunity.accountid = null OR opportunity.account.npe01__SYSTEMIsIndividual__c = true) ';   
            soqlStatement += 'AND (contact.npo02__household__c IN : hhIds OR  ';
            soqlStatement += '(contact.npo02__household__c = null AND contactid IN :conids)) ';
            if (useFiscalYear)
                soqlStatement += 'GROUP BY CUBE(contact.npo02__household__c, contactId, Fiscal_Year(opportunity.closeDate)) ';
            else
                soqlStatement += 'GROUP BY CUBE(contact.npo02__household__c, contactId, Calendar_Year(opportunity.closeDate)) ';
            soqlStatement += 'HAVING (contactId IN : conIds OR contactId = null) ';
                
            objectList.clear();
            objectList = database.query(soqlStatement);
            
            // invokes code to get the currency of npo02__CombinedRollupFieldset__c oppty
            opptyCurrencies = (isMultiCurrency() ? rcfFindCurrency(objectList) : null);
                
            for (sobject r : objectList) {
                
                // system.debug(Logginglevel.WARN, 'ROLLUP ROW: ' + r);
    
                // get the ids
                id cid = (id)(r.get('contactId'));
                id hhid = (id)(r.get('hhid'));
                    
                // process the result row, copying it into the contact record(s)
                // MS: we only want to fully calc the row if it is from the last few years - older years are only for calcing Best Year for contacts
                integer yr = (integer)r.get('CalendarYr');
                if (cid == null) { 
                    /*if (hhid != null && (yr >= startYear || yr==null) ) updateRollupFromResult((sobject)(householdsToUpdate.get(hhid)), r);*/
                    if (hhid != null && (yr >= startYear || yr==null) ) updateRollupFromResult((sobject)(householdsToUpdate.get(hhid)), r, opptyCurrencies);
                    // after doing regular processing, calc Best Contact Year stuff
                    // the rows are in year order, so just look start w/ the first yr, and increase as needed as we go
                    decimal yrAmt = (decimal)r.get('TotalOppAmount');
                    npo02__household__c HH = householdsToUpdate.get(hhid);
    
                } else {
                    // contact row
                    if ( yr >= startYear || yr==null) {
                        /*updateRollupFromResult((sobject)(contactsToUpdate.get(cid)), r);*/
                        updateRollupFromResult((sobject)(contactsToUpdate.get(cid)), r, opptyCurrencies);
                    }
                    // after doing regular processing, calc Best Contact Year stuff
                    // the rows are in year order, so just look start w/ the first yr, and increase as needed as we go
                    decimal yrAmt = (decimal)r.get('TotalOppAmount');
                    Contact con = contactsToUpdate.get(cid);
                }
            }
                
            // also do rollups for last N days
            soqlStatement = 'SELECT contact.npo02__household__c hhid, contactId, ';
            soqlStatement += 'SUM(Opportunity.Amount) TotalOppAmount, COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps ';
            soqlStatement += 'FROM OpportunityContactRole  ';
            soqlStatement += 'WHERE isPrimary=true AND opportunity.isWon=true  ';
            soqlStatement += 'AND (Opportunity.Amount != null) '; 
            if(areRecordTypesOnOpps()){
                soqlStatement += 'AND Opportunity.RecordTypeId NOT IN : recordTypesToExcludeCons ';
            }
            soqlStatement += 'AND Opportunity.Type NOT IN : oppTypesToExcludeCons ';
            soqlStatement += 'AND (opportunity.accountid = null OR opportunity.account.npe01__SYSTEMIsIndividual__c = true) ';   
            soqlStatement += 'AND (contact.npo02__household__c IN : hhIds OR  ';
            soqlStatement += '(contact.npo02__household__c = null AND contactid IN :conids)) ';
            soqlStatement += 'AND opportunity.closeDate >= LAST_N_DAYS:' + ndayrollup + ' ';
            soqlStatement += 'GROUP BY ROLLUP(contact.npo02__household__c, contactId) ';
            soqlStatement += 'HAVING (contactId IN : conIds OR contactId = null) ';
            
           objectList.clear();
           objectList = database.query(soqlStatement);
                
           for (sobject r : objectList) {
    
                //system.debug(Logginglevel.WARN, 'ROLLUP ROW: ' + r);
                
                // get the ids
                id cid = (id)(r.get('contactId'));
                id hhid = (id)(r.get('hhid'));
                    
                // process the result row, copying it into the contact record(s)
                if (cid == null) { 
                    if (hhid != null)
                        updateRollupFromResultLastNDays((sobject)(householdsToUpdate.get(hhid)), r);
                } else {
                    // contact row  
                    updateRollupFromResultLastNDays((sobject)(contactsToUpdate.get(cid)), r);
                }
            } 
    
            if (!mbrRecordTypes.isEmpty()) {
                // also do rollups for membership
                // if you need annual rollups for membership, uncomment the commented bits
                soqlStatement = 'SELECT contact.npo02__household__c hhid, contactId, ';
                soqlStatement += 'SUM(Opportunity.Amount) TotalOppAmount,  ';
                soqlStatement += 'MAX(Opportunity.CloseDate) LastCloseDate,  ';
                soqlStatement += 'MIN(Opportunity.npe01__membership_start_date__c) FirstStartDate, '; 
                soqlStatement += 'MAX(Opportunity.npe01__Membership_End_Date__c) LastEndDate,  ';
                soqlStatement += 'MAX(contact.npo02__household__r.npo02__MembershipEndDate__c) HHMembershipEnddate, ';
                soqlStatement += 'COUNT_DISTINCT(Opportunity.Id) NumberOfClosedOpps, ';
                soqlStatement += 'MAX(Opportunity.npo02__CombinedRollupFieldset__c) RollupFieldset ';
                soqlStatement += 'FROM OpportunityContactRole  ';
                soqlStatement += 'WHERE isPrimary=true AND opportunity.isWon=true '; 
                soqlStatement += 'AND (Opportunity.Amount != null) '; 
                if(areRecordTypesOnOpps()){
                    soqlStatement += 'AND Opportunity.RecordTypeId IN : mbrRecordTypes ';
                }
                soqlStatement += 'AND Opportunity.Type NOT IN : oppTypesToExcludeCons ';
                soqlStatement += 'AND (opportunity.accountid = null OR opportunity.account.npe01__SYSTEMIsIndividual__c = true)  '; 
                soqlStatement += 'AND (contact.npo02__household__c IN : hhIds OR  ';
                soqlStatement += '(contact.npo02__household__c = null AND contactid IN :conids)) ';
                soqlStatement += 'GROUP BY CUBE(contact.npo02__household__c, contactId) ';
                soqlStatement += 'HAVING (contactId IN : conIds OR contactId = null) ';
               
                objectList.clear();
                objectList = database.query(soqlStatement);
                
                // invokes code to get the currency of npo02__CombinedRollupFieldset__c oppty
                opptyCurrencies = (isMultiCurrency() ? rcfFindCurrency(objectList) : null);
                
                for (sobject r : objectList) {
                            
                    // get the ids
                    id cid = (id)(r.get('contactId'));
                    id hhid = (id)(r.get('hhid'));
                        
                    // process the result row, copying it into the contact record(s)
                    if (cid == null) { 
                        if (hhid != null)
                            /*updateRollupFromResultMembership((sobject)(householdsToUpdate.get(hhid)), r);*/
                            updateRollupFromResultMembership((sobject)(householdsToUpdate.get(hhid)), r, opptyCurrencies);
                    } else {
                        // contact row  
                        /*updateRollupFromResultMembership((sobject)(contactsToUpdate.get(cid)), r);*/
                        updateRollupFromResultMembership((sobject)(contactsToUpdate.get(cid)), r, opptyCurrencies);
                    }
                }
            }
        }

        // remove any records that have not changed
        for (id cid : conIds) {
            contact c1 = cmap.get(cid);
            contact c2 = contactsToUpdate.get(cid);
            
            if ((c1.npo02__TotalOppAmount__c == c2.npo02__TotalOppAmount__c &&
                    c1.npo02__OppAmountLastYear__c == c2.npo02__OppAmountLastYear__c && 
                    c1.npo02__OppAmount2YearsAgo__c == c2.npo02__OppAmount2YearsAgo__c &&
                    c1.npo02__OppAmountLastNDays__c == c2.npo02__OppAmountLastNDays__c &&
                    c1.npo02__OppAmountThisYear__c == c2.npo02__OppAmountThisYear__c &&
                    c1.npo02__TotalMembershipOppAmount__c == c2.npo02__TotalMembershipOppAmount__c &&
                    c1.npo02__LastCloseDate__c == c2.npo02__LastCloseDate__c &&
                    c1.npo02__MembershipEndDate__c == c2.npo02__MembershipEndDate__c &&
                    c1.npo02__MembershipJoinDate__c == c2.npo02__MembershipJoinDate__c
                    ) && hasContactRollups == false)
                contactsToUpdate.remove(cid);
        }
        
        for (id hhid : hhIds) {
            npo02__household__c hh1 = hhmap.get(hhid); 
            npo02__household__c hh2 = householdsToUpdate.get(hhid);
            if ((hh1.npo02__TotalOppAmount__c == hh2.npo02__TotalOppAmount__c && 
                    hh1.npo02__OppAmountLastNDays__c == hh2.npo02__OppAmountLastNDays__c &&
                    hh1.npo02__OppAmountThisYear__c == hh2.npo02__OppAmountThisYear__c &&
                    hh1.npo02__OppAmountLastYear__c == hh2.npo02__OppAmountLastYear__c &&
                    hh1.npo02__OppAmount2YearsAgo__c == hh2.npo02__OppAmount2YearsAgo__c &&
                    hh1.npo02__TotalMembershipOppAmount__c == hh2.npo02__TotalMembershipOppAmount__c &&
                    hh1.npo02__LastCloseDate__c == hh2.npo02__LastCloseDate__c &&
                    hh1.npo02__MembershipEndDate__c == hh2.npo02__MembershipEndDate__c && 
                    hh1.npo02__MembershipJoinDate__c == hh2.npo02__MembershipJoinDate__c
                    ) && hasHouseholdRollups == false)
                householdsToUpdate.remove(hhid);
        }

        // update all the contacts from this batch 
        if (!contactsToUpdate.isEmpty()) update contactsToUpdate.values();              
        if (!householdsToUpdate.isEmpty()) update householdsToUpdate.values();              
    }
    
    public void rollupForOppTrigger( map<id, opportunity> newOpps, map<id, opportunity> oldOpps ) {
    // find contacts and accounts affected and then roll them up

        if (triggerRollupEnabled) {
            
            set<id> modifiedContactOpps = new set<id>();
            set<id> acctsToReroll = new set<id>(); 
            
            boolean includedRecordType = false;
            Boolean recordTypeChanged = false;
            if (newOpps == null) {
    
                // it is a delete
                for (id oid : oldOpps.keySet()) {
                    opportunity o = oldOpps.get(oid);                    
                    
                    if (o.isWon && o.Amount != null) {
                        includedRecordType = false;
                        if (areRecordTypesOnOpps()){
                            includedRecordType = mbrRecordTypes.contains((id)o.get('recordTypeId')) ||
                                !recordTypesToExcludeCons.contains((id)o.get('recordTypeId'));
                        } else {
                            includedRecordType = true;
                        }
                        if (((o.npe01__Is_Opp_From_Individual__c == 'true' || o.accountid == null) || alwaysRollupToPrimaryContact) &&
                            includedRecordType &&
                            (!oppTypesToExcludeCons.contains(o.type))) {
                        
                            modifiedContactOpps.add(o.id);
                        }
                        if (areRecordTypesOnOpps()){
                            includedRecordType = false;
                            includedRecordType = mbrRecordTypes.contains((id)o.get('recordTypeId')) ||
                                !recordTypesToExcludeAccts.contains((id)o.get('recordTypeId'));
                        } else {
                            includedRecordType = true;
                        }
                        if (o.accountId != null && includedRecordType && (!oppTypesToExcludeAccts.contains(o.type))) {                              
                            acctsToReroll.add(o.accountId);
                        }
                    }
                }
            } else if (oldOpps == null) {
                // for insert, find the closed opps that qualify
                for (id oid : (newOpps.keySet())) {
                    opportunity o = newOpps.get(oid);
                    
                    if (o.isWon && o.Amount != null) {
                        if (areRecordTypesOnOpps()){
                            includedRecordType = false;
                            includedRecordType = !mbrRecordTypes.contains((id)o.get('recordTypeId')) ||
                                !recordTypesToExcludeCons.contains((id)o.get('recordTypeId'));
                        } else {
                            includedRecordType = true;
                        }
                        if (((o.npe01__Is_Opp_From_Individual__c == 'true' || o.accountid == null) || (alwaysRollupToPrimaryContact)) && includedRecordType
                             && (!oppTypesToExcludeCons.contains(o.type))) {
                         
                            modifiedContactOpps.add(o.id);
                        } 
                        if (areRecordTypesOnOpps()){
                            includedRecordType = false;
                            includedRecordType = !mbrRecordTypes.contains((id)o.get('recordTypeId')) ||
                                !recordTypesToExcludeAccts.contains((id)o.get('recordTypeId'));
                        } else {
                            includedRecordType = true;
                        }
                        if (o.accountId != null && includedRecordType && (!oppTypesToExcludeAccts.contains(o.type))) {

                            acctsToReroll.add(o.accountId);
                        }
                    }
                } 
                
            } else {
                system.debug('In the Update block');
                // for update, find the opps that are changed in any important way
                for (id oid : (newOpps.keySet())) {
                    
                    // compare old and new
                    opportunity o = newOpps.get(oid);
                    opportunity oldOpp = oldOpps.get(oid);
                    
                    
                    if (areRecordTypesOnOpps()){
                        recordTypeChanged = false;
                        recordTypeChanged = ((id)o.get('recordTypeId') != (id)oldOpp.get('recordTypeId'));
                    }
                    // look for opps that have changed in any important way
                    if (o.isWon != oldOpp.isWon || (o.isWon && 
                        ((o.Amount != oldOpp.Amount) ||
                        recordTypeChanged || 
                        (o.type != oldOpp.type) ||
                        (o.closeDate != oldOpp.closeDate) ||
                        (o.accountId != oldOpp.accountId)))) { 
                        system.debug('Passed Opp Change Check');
                        if (o.npe01__Is_Opp_From_Individual__c == 'true' || o.accountid == null || alwaysRollupToPrimaryContact) {
                            modifiedContactOpps.add(o.id);
//                          system.debug('Added to Cons to Update List' + o);
                        }
                        if (o.accountId != null) {
                            acctsToReroll.add(o.accountId); 
                        }
                    }       
                }           
            }   
            
//          system.debug('Modified Contact Opps' + modifiedContactOpps);
            
            // use the contact roles to find the contacts and households
            if (!modifiedContactOpps.isEmpty()) {

                if ((Limits.getLimitFutureCalls() - Limits.getFutureCalls()) > 5) {
//                  system.debug('Passed limit check for con rollup update');
                    rollupHouseholdsFuture(modifiedContactOpps);
                    
                } else {
                    system.debug(Logginglevel.WARN, Label.Opportunity_Rollup_Future_Call_Limit);
                }
            }

            // roll them up
            if (!acctsToReroll.isEmpty()) {
                
                boolean rollupNow = false;
                map<id, account> amap;
                if (acctsToReroll.size() == 1) {                    
                    /*amap = new map<id, account>(
                        [select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastNDays__c,                        
                        npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c, npo02__TotalMembershipOppAmount__c,
                        npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__OppsClosedThisYear__c,
                        npo02__OppsClosedLastYear__c, npo02__OppsClosedLastNDays__c, npo02__OppsClosed2YearsAgo__c 
                        from account where id in :acctsToReroll ]);*/
                    amap = new map<id, account>((list<Account>)Database.query('select id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastNDays__c,'+ 
                       'npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c, npo02__TotalMembershipOppAmount__c,'+
                       'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__OppsClosedThisYear__c,'+
                       'npo02__OppsClosedLastYear__c, npo02__OppsClosedLastNDays__c, npo02__OppsClosed2YearsAgo__c '+
                       (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+             
                       'from account where id in :acctsToReroll'));
                }
               
                //if there are any accounts with more than 25 opps, 
                //default back to the @future method for rollups
                
                if (amap != null){
                    rollupNow = true;   
                    for (Account a : amap.values()){
                        decimal oppCount = a.npo02__NumberOfClosedOpps__c;
                        rollupNow = !(oppCount != null && oppCount > 25);
                    }
                }                        
                // for a single account with fewer than 200 opps, roll up immediately - otherwise future
                if (rollupNow)
                    rollupAccounts( amap );
                else if ((Limits.getLimitFutureCalls() - Limits.getFutureCalls()) > 5)
                    rollupAccountsFuture( acctsToReroll );
                else
                    system.debug(Logginglevel.WARN, Label.Opportunity_Rollup_Future_Call_Limit);                
            }
        }   
    }

    public void rollupAll() {
        rollupAllAccounts();
        rollupAllContacts(); 
    }   

    public void rollupAllAccounts() {

        // we can handle up to 10000 query rows total, which is about 3000 opps in a batch
        // this calculation very conservatively reduces batch size to avoid hitting the limit
        integer batchSize = 200;
        list<account> topAccount = [select npo02__NumberOfClosedOpps__c from account 
            where npo02__NumberOfClosedOpps__c != null 
            order by npo02__NumberOfClosedOpps__c desc limit 1];
        if (!topAccount.isEmpty()) {
            decimal highestCount = topAccount[0].npo02__NumberOfClosedOpps__c;
            if (highestCount > 15) {
                batchSize = (3000 / highestCount).intValue() + 1;
            }
        }

        // start the batch to roll up all accounts
        BATCH_OppRollup batch = new BATCH_OppRollup( 'SELECT id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastNDays__c, ' +  
        'npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c, npo02__TotalMembershipOppAmount__c, ' +
        'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__OppsClosedThisYear__c, ' +
        'npo02__OppsClosedLastYear__c, npo02__MembershipJoinDate__c, npo02__MembershipEndDate__c, npo02__OppsClosedLastNDays__c, npo02__OppsClosed2YearsAgo__c ' +
        (isMultiCurrency() ? ', CurrencyIsoCode ' : '') + 
        'FROM account' + (isTest ? ' WHERE name like \'%test%\' LIMIT 200' : '') );
        id batchProcessId = database.executeBatch(batch, batchSize);        
    }   
        
    public void rollupAllContacts() {

        // we can handle up to 10000 query rows total, which is about 3000 opps in a batch
        // this calculation very conservatively reduces batch size to avoid hitting the limit
        integer batchSize = 200;
        list<npo02__household__c> topHousehold = [select npo02__NumberOfClosedOpps__c from npo02__household__c 
            where npo02__NumberOfClosedOpps__c != null 
            order by npo02__NumberOfClosedOpps__c desc limit 1];
        if (!topHousehold.isEmpty()) {
            decimal highestCount = topHousehold[0].npo02__NumberOfClosedOpps__c;
            if (highestCount > 15) {
                batchSize = (3000 / highestCount).intValue() + 1;
            }
        }

        BATCH_OppRollup batch = new BATCH_OppRollup( 'SELECT id, npo02__TotalOppAmount__c, ' +
            'npo02__OppAmountThisYear__c, npo02__TotalMembershipOppAmount__c, ' +
            'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipJoinDate__c, npo02__MembershipEndDate__c, ' +
            'npo02__OppAmountLastNDays__c, npo02__LastCloseDate__c, npo02__NumberOfClosedOpps__c ' +
            (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+              
            ' FROM npo02__household__c ' + 
            (isTest ? ' WHERE name like \'%doppleganger%\' LIMIT 200' : '') );
        id batchProcessId = database.executeBatch(batch, batchSize);        
    }

    public static void updateRollupFromResult(sobject obj, sobject r, map<id, Opportunity> opptyCurrencies) {
    // used for single and batch rollups, this maps query results to the right fields

        // get the fiscal year, total amount, and opp count for this result row     
        integer fy = (integer)(r.get('CalendarYr'));
        decimal amt = (decimal)(r.get('TotalOppAmount'));
        integer cnt = (integer)(r.get('NumberOfClosedOpps'));               
        
        // split the special field to get the last opp id and amount
        string[] rcf = ((string)(r.get('RollupFieldset'))).split(';\\|;',-4);
        decimal lastAmt = (rcf.size() > 1 && rcf[1] != '') ? decimal.valueOf(rcf[1]) : null;
        
        // calculate amounts into correct currency if needed
        if(isMultiCurrency()){
            amt = ConvertFromCorporate((string)obj.get('CurrencyIsoCode'),amt);
            if(lastAmt != null && rcf.size() > 4 && rcf[4] != '')
                lastAmt = ConvertCurrency((string)opptyCurrencies.get((Id)rcf[4]).get('CurrencyISOCode'),(string)obj.get('CurrencyIsoCode'),lastAmt);           
        }
        
        // check if this is an annual total or account total
        if (fy != null) {

            // put the fiscal year total in the right fields
            integer thisYear = system.today().year();
            if (fy == thisYear) {
                obj.put('npo02__OppAmountThisYear__c', amt); 
                obj.put('npo02__OppsClosedThisYear__c', cnt); 
            } else if (fy == (thisYear - 1)) {
                obj.put('npo02__OppAmountLastYear__c', amt); 
                obj.put('npo02__OppsClosedLastYear__c', cnt); 
            } else if (fy == (thisYear - 2) ) {
                obj.put('npo02__OppAmount2YearsAgo__c', amt); 
                obj.put('npo02__OppsClosed2YearsAgo__c', cnt); 
            } 
                
        } else { 

            // fill in summary totals
            obj.put('npo02__TotalOppAmount__c', amt);
            obj.put('npo02__NumberOfClosedOpps__c', cnt);               
            obj.put('npo02__LastOppAmount__c', lastAmt);
            obj.put('npo02__FirstCloseDate__c', r.get('FirstCloseDate')); //date
            obj.put('npo02__LastCloseDate__c', r.get('LastCloseDate')); //date
            
            // calculate amounts into correct currency if needed
            if(isMultiCurrency())
            {
               obj.put('npo02__AverageAmount__c', ConvertFromCorporate((string)obj.get('CurrencyIsoCode'),(decimal)r.get('AverageAmount'))); 
               obj.put('npo02__SmallestAmount__c', ConvertFromCorporate((string)obj.get('CurrencyIsoCode'),(decimal)r.get('SmallestAmount'))); 
               obj.put('npo02__LargestAmount__c', ConvertFromCorporate((string)obj.get('CurrencyIsoCode'),(decimal)r.get('LargestAmount'))); 
            }
            else
            {
               obj.put('npo02__AverageAmount__c', (decimal)(r.get('AverageAmount'))); 
               obj.put('npo02__SmallestAmount__c', (decimal)(r.get('SmallestAmount'))); 
               obj.put('npo02__LargestAmount__c', (decimal)(r.get('LargestAmount'))); 
            }
        }
        
        //deal with user rollups
        if (userRollups.size() > 0){
            for (string s : userRollups.keyset()){
                if (obj.getSObjectType().getDescribe().getName() == userRollups.get(s).Object_Name__c){
                    User_Rollup_Field_Settings__c urfs = userRollups.get(s);
                    string x = urfs.Name;                   
                    if (r.get(x) != null)
                       obj.put(urfs.Target_Field__c, r.get(x));
                }
            }
        } 
    }

    public static void updateRollupFromResultLastNDays(sobject obj, sobject r) {
    // used for single and batch rollups, this maps query results to the right fields
        
        // get the fiscal year, total amount, and opp count for this result row     
        decimal amt = (decimal)(r.get('TotalOppAmount'));
        integer cnt = (integer)(r.get('NumberOfClosedOpps'));               
        
        // calculate amounts into correct currency if needed
        if(isMultiCurrency())
           amt = ConvertFromCorporate((string)obj.get('CurrencyIsoCode'),amt);
        
        // fill in totals
        obj.put('npo02__OppAmountLastNDays__c', amt);               
        obj.put('npo02__OppsClosedLastNDays__c', cnt);
    }

    public static void updateRollupFromResultMembership(sobject obj, sobject r, map<id, Opportunity> opptyCurrencies) {
    // used for single and batch rollups, this maps query results to the right fields
        
        // get the fiscal year, total amount, and opp count for this result row     
        //integer fy = (integer)(r.get('CalendarYr'));
        decimal amt = (decimal)(r.get('TotalOppAmount'));
        integer cnt = (integer)(r.get('NumberOfClosedOpps'));               

        // split the special field to get the last opp id and amount
        string[] rcf = ((string)(r.get('RollupFieldset'))).split(';\\|;',-4);
        decimal lastAmt = (rcf.size() > 1 && rcf[1] != null) ? decimal.valueOf(rcf[1]) : null;
        string lastMemberLevel = (rcf.size() > 2) ? rcf[2] : null;
        string lastMemberOrigin = (rcf.size() > 3) ? rcf[3] : null;
        // calculate amounts into correct currency if needed
        if(isMultiCurrency()){
           amt = ConvertFromCorporate((string)obj.get('CurrencyIsoCode'),amt);
           if(lastAmt != null && rcf.size() > 4 && rcf[4] != '')
               lastAmt = ConvertCurrency((string)opptyCurrencies.get((Id)rcf[4]).get('CurrencyISOCode'),(string)obj.get('CurrencyIsoCode'),lastAmt);           
        }

        // check if this is an annual total or account total
/* ADD FIELDS AND UNCOMMENT IF YOU NEED ANNUAL MEMBERSHIP TOTAL BREAKOUT
        if (fy != null) {

            // put the fiscal year total in the right fields
            integer thisYear = system.today().year();
            
            if (fy == thisYear) {
                obj.put('Membershipnpo02__OppAmountThisYear__c', amt); 
                obj.put('MembershipOppsThisYear__c', cnt); 
            } else if (fy == (thisYear - 1)) {
                obj.put('Membershipnpo02__OppAmountLastYear__c', amt); 
                obj.put('MembershipOppsLastYear__c', cnt); 
            } else if (fy == (thisYear - 2) ) {
                obj.put('Membershipnpo02__OppAmount2YearsAgo__c', amt); 
                obj.put('MembershipOpps2YearsAgo__c', cnt); 
            } 
        } else {
*/              
            // fill in summary totals
            obj.put('npo02__TotalMembershipOppAmount__c', amt);
            obj.put('npo02__NumberOfMembershipOpps__c', cnt);               
            obj.put('npo02__LastMembershipDate__c', (date)(r.get('LastCloseDate')));                
            obj.put('npo02__LastMembershipAmount__c', lastAmt);                 
            obj.put('npo02__LastMembershipLevel__c', lastMemberLevel);              
            obj.put('npo02__LastMembershipOrigin__c', lastMemberOrigin);                
            obj.put('npo02__MembershipJoinDate__c', (date)(r.get('FirstStartDate'))); 
            obj.put('npo02__MembershipEndDate__c', (date)(r.get('LastEndDate')));               
//      }
    }
    
    /*********** Multi-Currency Support Methods ***********/

    //returns a boolean if we are in a multi-currency org or not.
    //on first execution sets up static variables etc
    public static boolean isMultiCurrency(){
        
        if (multiCurrency==null){
            //create currency field handles for later dynamic dml
            cfOppty = Schema.sObjectType.Opportunity.fields.getMap().get('CurrencyIsoCode');
            cfAccount = Schema.sObjectType.Account.fields.getMap().get('CurrencyIsoCode');
            cfHousehold = Schema.sObjectType.npo02__household__c.fields.getMap().get('CurrencyIsoCode');
            cfContact = Schema.sObjectType.Contact.fields.getMap().get('CurrencyIsoCode');

            String queryExchangeRates = 'select IsoCode,ConversionRate,IsCorporate from CurrencyType';
            SObjectType soCurrencyType = Schema.getGlobalDescribe().get('CurrencyType'); 

            //are we in a multi-currency org?
            if (cfOppty != null && cfAccount != null && cfHousehold != null && cfContact != null && soCurrencyType != null){
                multiCurrency = true;
 
                map<string,SObjectField> ctFields = soCurrencyType.getDescribe().fields.getMap();
                SObjectField ctIsoCode = ctFields.get('IsoCode');
                SObjectField ctConversionRate = ctFields.get('ConversionRate');
                SObjectField ctCorporate = ctFields.get('IsCorporate');

                //iterate over all the currencies in the org (inc. inactive ones as they may have been used previously)
                //this allows us to put them in a map and use the ISO code as key and also set the corporate
                for(sObject ct: Database.query(queryExchangeRates)){
                    exchangeRates.put((string)ct.get(ctIsoCode),(decimal)ct.get(ctConversionRate));
                    if((boolean)ct.get(ctCorporate))currCorporate=(string)ct.get(ctIsoCode);
                }
            }
            else
                multiCurrency = false; 
        }
        
        return multiCurrency;
        }

    //do a conversion from amount in corporate currency to the currency specified by the ISO code
    public static decimal ConvertFromCorporate(String ISO,Decimal amt){
        if(currCorporate == ISO || currCorporate == null) // no need to convert
            return amt;
        else //return value to 2DP
            return (amt * exchangeRates.get(ISO)).setScale(2) ;
    }

    public static decimal ConvertCurrency(String fromISO, String toISO, Decimal amt){
        if(fromISO == toISO) // no need to convert
            return amt;
        else //return value to 2DP
            return ((amt / exchangeRates.get(fromISO)) * exchangeRates.get(toISO)).setScale(2) ;
    }
 
    //takes the Ids of opptys in the npo02__CombinedRollupFieldset__c field, and looks up the currency of that record
    //only used in multi currency orgs
    //returns a map of those Ids and the associated oppty
    public map<Id,Opportunity> rcfFindCurrency(list<sobject> objectList){
        //new set to hold the opptys we need to query for
        set<Id> opptysForCurrency = new set<Id>();

        //iterate over objects provided to us
        for (sobject r : objectList){
            //pull Id from rollup field and add to set
            string[] rcf = ((string)(r.get('RollupFieldset'))).split(';\\|;',-4);
            if(rcf.size() > 1 && rcf[1] != '')
                opptysForCurrency.add((Id)rcf[4]);
        }
        
        if (!objectlist.isEmpty()){
            //query for oppty and currencycode for all Ids in set.
            string soqlStatement = 'SELECT Id,CurrencyIsoCode FROM Opportunity WHERE Id in :opptysForCurrency';
            map<Id,Opportunity> opptyCurrencies = new map<Id,Opportunity>((list<Opportunity>)Database.query(soqlStatement));
            return opptyCurrencies;
        }
        else
            return null;
        
    }

    /************ TESTS ***************/
    
    static testMethod void testGivingRollup () {
        isTest = true;
        
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
        //if(giftRecordTypeNameForTests!=''){
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
            
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            Date datClose = System.Today();
                
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
    
            // create new opps
            Opportunity[] newOpps = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose, 100 , giftRecordTypeNameForTests ,null);
            //add a null amount opp
            
            newOpps.add(new Opportunity(
                Name = 'Test Opp 45',
                CloseDate = datClose,
                StageName = UnitTestData.getClosedWonStage(),
                npe01__Contact_Id_for_Role__c = TestCons[0].Id));
            // insert the opp(s)
            Test.StartTest();
            insert newOpps;
            Test.StopTest();
            
            //now test that a contact has received the proper member stats from the trigger
            id FirstConId = TestCons[0].id;
            Contact UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 100 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );      
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c);
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountLastYear__c);
    
            // now roll up manually
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
            
            //also exercise the non-future methods to make sure the code runs
            /*npo02__household__c[] hhs = [SELECT id, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipEndDate__c, npo02__MembershipJoinDate__c FROM npo02__household__c WHERE id = :UpdatedCon.npo02__household__r.id LIMIT 1];*/
            
            id hhid = UpdatedCon.npo02__household__r.id;
            
            npo02__household__c[] hhs = database.query('SELECT id, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, '+
            'npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, '+
            'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipEndDate__c, npo02__MembershipJoinDate__c '+
            (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+      
            'FROM npo02__household__c WHERE id = :hhid LIMIT 1');

            rg = new OpportunityRollups();
            rg.rollupHousehold(hhs[0].id);
            rg = new OpportunityRollups();
            rg.rollupHouseholds(hhs);
    
            //make sure the values are still right
            UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 100 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );      
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c);
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountLastYear__c);
        //}
    }
    
    static testMethod void testGivingRollupIndividual () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
            
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.BUCKET_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            Date datClose = System.Today();
                
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
    
            // create new opps
            Opportunity[] newOpps = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose, 100 , giftRecordTypeNameForTests ,null);
    
            // insert the opp(s)
            Test.StartTest();
            insert newOpps;
            Test.StopTest();
            
            //now test that a contact has received the proper member stats from the trigger
            id FirstConId = TestCons[0].id;
            Contact UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c, npo02__household__r.npo02__MembershipEndDate__c, npo02__MembershipJoinDate__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 100 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );      
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c);
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountLastYear__c);
    
            // now roll up manually
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
            
            //also exercise the non-future methods to make sure the code runs
            /*npo02__household__c[] hhs = [SELECT npo02__MembershipJoinDate__c, npo02__MembershipEndDate__c, id, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM npo02__household__c WHERE id = :UpdatedCon.npo02__household__r.id LIMIT 1];*/
            
            id hhid = UpdatedCon.npo02__household__r.id;
            npo02__household__c[] hhs = database.query('SELECT id, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, '+
            'npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, '+
            'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipJoinDate__c, npo02__MembershipEndDate__c '+
            (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+      
            'FROM npo02__household__c WHERE id = :hhid LIMIT 1');
            
            rg = new OpportunityRollups();
            rg.rollupHousehold(hhs[0].id);
            rg = new OpportunityRollups();
            rg.rollupHouseholds(hhs);
    
            //make sure the values are still right
            UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 100 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );      
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c);
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountLastYear__c);
        
    }
    
    static testMethod void testGivingRollupExcludedRT () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
        if(giftRecordTypeNameForTests!=''){
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = giftRecordTypeNameForTests,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = giftRecordTypeNameForTests,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
            
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            Date datClose = System.Today();
                
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
    
            // create new opps
            Opportunity[] newOpps = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose, 100 , giftRecordTypeNameForTests ,null);
    
            // insert the opp(s)
            Test.StartTest();
            insert newOpps;
            Test.StopTest();
            
            //now test that a contact has received the proper member stats from the trigger
            id FirstConId = TestCons[0].id;
            Contact UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 0 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 0 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );        
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountThisYear__c);
    
            // now roll up manually
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
            
            //also exercise the non-future methods to make sure the code runs
            /*npo02__household__c[] hhs = [SELECT id, npo02__MembershipJoinDate__c, npo02__MembershipEndDate__c, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM npo02__household__c WHERE id = :UpdatedCon.npo02__household__r.id LIMIT 1];*/
            id hhid = UpdatedCon.npo02__household__r.id;
            npo02__household__c[] hhs = database.query('SELECT id, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, '+
            'npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, '+
            'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipJoinDate__c, npo02__MembershipEndDate__c '+
            (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+      
            'FROM npo02__household__c WHERE id = :hhid LIMIT 1');
            
            rg = new OpportunityRollups();
            rg.rollupHousehold(hhs[0].id);
            rg = new OpportunityRollups();
            rg.rollupHouseholds(hhs);
    
            //make sure the values are still right
            UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 0 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 0 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );        
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountThisYear__c);
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountLastYear__c);
        }
    }
    
    
   static testMethod void testGivingRollupAlwaysPrimary () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = true,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
            
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            Date datClose = System.Today();
            // create account
            account testacct = new account(name='testacct');
            insert testacct;
            // create & insert contact(s)
            Contact[] TestCons = new contact[]{ new contact(
                FirstName= npe01.Constants.CONTACT_FIRSTNAME_FOR_TESTS,
                LastName= npe01.Constants.CONTACT_LASTNAME_FOR_TESTS,
                npe01__Private__c=false,
                AccountId = testacct.id,
                npe01__WorkEmail__c = npe01.Constants.CONTACT_EMAIL_FOR_TESTS, 
                npe01__Preferred_Email__c = npe01.Constants.CONTACT_PREFERRED_EMAIL_FOR_TESTS,
                npe01__WorkPhone__c = npe01.Constants.CONTACT_PHONE_FOR_TESTS,
                npe01__PreferredPhone__c = npe01.Constants.CONTACT_PREFERRED_PHONE_FOR_TESTS
            ) };
            insert TestCons;
    
            // create new opps
            Opportunity[] newOpps = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose, 100 , giftRecordTypeNameForTests ,null);
    
            // insert the opp(s)
            Test.StartTest();
            insert newOpps;
            Test.StopTest();
            
            //now test that a contact has received the proper member stats from the trigger
            id FirstConId = TestCons[0].id;
            Contact UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 100 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );      
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c);
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountLastYear__c);
    
            // now roll up manually
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
            
            //also exercise the non-future methods to make sure the code runs
            /*npo02__household__c[] hhs = [SELECT id, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipEndDate__c, npo02__MembershipJoinDate__c FROM npo02__household__c WHERE id = :UpdatedCon.npo02__household__r.id LIMIT 1];*/
            id hhid = UpdatedCon.npo02__household__r.id;
            npo02__household__c[] hhs = database.query('SELECT id, npo02__TotalOppAmount__c, npo02__LastCloseDate__c, '+
            'npo02__TotalMembershipOppAmount__c, npo02__OppAmountLastNDays__c, npo02__OppAmountThisYear__c, '+
            'npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, npo02__MembershipEndDate__c, npo02__MembershipJoinDate__c '+
            (isMultiCurrency() ? ', CurrencyIsoCode ' : '')+      
            'FROM npo02__household__c WHERE id = :hhid LIMIT 1');
            
            rg = new OpportunityRollups();
            rg.rollupHousehold(hhs[0].id);
            rg = new OpportunityRollups();
            rg.rollupHouseholds(hhs);
    
            //make sure the values are still right
            UpdatedCon = [SELECT id, account.npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__household__c, npo02__household__r.npo02__TotalOppAmount__c, npo02__TotalOppAmount__c FROM Contact WHERE Id = :FirstConId];
    
            System.AssertEquals ( 100 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__household__r.npo02__TotalOppAmount__c );      
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c);
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmountLastYear__c);
        
    }
    
 static testMethod void testMemberRollup () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
        String membershipRecordTypeNameForTests = RecordTypes.getRecordTypeNameForMembershipTests('Opportunity');
        if(membershipRecordTypeNameForTests!=''){
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = membershipRecordTypeNameForTests
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
                    
            Date datClose = System.Today();
                
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
    
            // create new opps
            Opportunity[] newOpps = UnitTestData.OppsForContactList (
                TestCons,
                null,
                UnitTestData.getClosedWonStage(),
                datClose,
                100,
                householdSettingsForTests.Membership_Record_Types__c,
                null
            );
    
            system.debug(newOpps);
            
            // insert the opp(s)
            Test.StartTest();
            newOpps[0].npe01__Membership_Origin__c = 'Renewal';
            insert newOpps;
            Test.StopTest();
            
            //now test that a contact has received the proper member stats from the trigger
            id FirstConId = TestCons[0].id;
            Contact UpdatedCon = [SELECT id, npo02__TotalMembershipOppAmount__c,npo02__LastMembershipOrigin__c,
                npo02__LastMembershipAmount__c, npo02__LastMembershipDate__c 
                from contact where id =: firstconid];
            System.AssertEquals ( 100 , updatedcon.npo02__TotalMembershipOppAmount__c );        
            System.AssertEquals ( 100 , updatedcon.npo02__LastMembershipAmount__c );        
            System.AssertEquals ( 'Renewal' , updatedcon.npo02__LastMembershipOrigin__c );      
            System.AssertEquals ( system.today() , updatedcon.npo02__LastMembershipDate__c );   
        }   
    }
    
    static testMethod void testGivingRollupAcct () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
        String membershipRecordTypeNameForTests = RecordTypes.getRecordTypeNameForMembershipTests('Opportunity');

            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            Date datClose = System.Today();
    
            // create account
            account testacct = new account(name='testacct');
            insert testacct;
            opportunity newOpp =
                 new opportunity (
                    name = 'testopp',
                    accountid = testacct.id, 
                    stagename=UnitTestData.getClosedWonStage(),
                    closedate=datClose, amount=33333
                 );
            if(areRecordTypesOnOpps()){
                newOpp.put('RecordTypeId',RecordTypes.GetRecordTypeId('Opportunity', giftRecordTypeNameForTests));
            }
            // insert the opp(s)
            Test.StartTest();
            insert newOpp;
            Test.StopTest();
            
            // test whether the trigger worked      
            account updatedAcct = [select id, npo02__TotalOppAmount__c from account where id =: testacct.id];       
            System.AssertEquals ( 33333 , updatedAcct.npo02__TotalOppAmount__c );       
    
            // now roll up manually
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupAccount(testacct.id);
    
            updatedAcct = [select id, npo02__TotalOppAmount__c from account where id =: testacct.id];
            System.AssertEquals ( 33333 , updatedAcct.npo02__TotalOppAmount__c );           
        
    }   

    static testMethod void testGivingRollupAcctMembership () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
        String membershipRecordTypeNameForTests = RecordTypes.getRecordTypeNameForMembershipTests('Opportunity');
        if(membershipRecordTypeNameForTests!=''){
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = membershipRecordTypeNameForTests
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            Date datClose = System.Today();
    
            // create account
            account testacct = new account(name='testacct');
            insert testacct;
            opportunity newOpp =
                 new opportunity (name = 'testopp', accountid = testacct.id, 
                                    npe01__member_level__c = 'Gold', npe01__membership_origin__c = 'New',
                                    stagename=UnitTestData.getClosedWonStage(), closedate=datClose, amount=33333);
            newOpp.put('RecordTypeId',RecordTypes.GetRecordTypeId('Opportunity', householdSettingsForTests.Membership_Record_Types__c));
            // insert the opp(s)
            Test.StartTest();
            insert newOpp;
            Test.StopTest();
            // test whether the trigger worked      
            account updatedAcct = [select id, npo02__TotalMembershipOppAmount__c, npo02__LastMembershipDate__c,
                npo02__LastMembershipAmount__c, npo02__LastMembershipLevel__c, npo02__LastMembershipOrigin__c
                from account where id =: testacct.id];      
            System.AssertEquals ( 33333 , updatedAcct.npo02__TotalMembershipOppAmount__c );     
            System.AssertEquals ( system.today() , updatedAcct.npo02__LastMembershipDate__c );      
            System.AssertEquals ( 33333 , updatedAcct.npo02__LastMembershipAmount__c );     
            System.AssertEquals ( 'Gold' , updatedAcct.npo02__LastMembershipLevel__c );     
            System.AssertEquals ( 'New' , updatedAcct.npo02__LastMembershipOrigin__c );
            
            // now roll up manually
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupAccount(testacct.id);
    
            updatedAcct = [select id, npo02__TotalMembershipOppAmount__c from account where id =: testacct.id];
            System.AssertEquals ( 33333 , updatedAcct.npo02__TotalMembershipOppAmount__c );     
        }
    }   

    static testMethod void testGivingRollupBatch () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');

            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
                
            Date datClose = System.Today();
                
            // create & insert contact(s)
            Contact[] TestCons = UnitTestData.CreateMultipleTestContacts ( 50 ) ;
            insert TestCons;
    
            // create new opps
            Opportunity[] newOpps = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose, 1000 , giftRecordTypeNameForTests ,null);
    
            account testacct = new account(name='testacct');
            insert testacct;
    
            // test the batch rollup method
            Test.StartTest();
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupAll();
            Test.StopTest();
        
    }   

    static testMethod void OneContactMultipleOpps() {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
        String membershipRecordTypeNameForTests = RecordTypes.getRecordTypeNameForMembershipTests('Opportunity');
        if(membershipRecordTypeNameForTests!=''){
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = membershipRecordTypeNameForTests
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
                
            integer howMany = 1;
            Date datToday = System.Today();
            Date dat1YearAgo = Date.newInstance( datToday.year()-1,1,1);
            Date dat2YearAgo = Date.newInstance( datToday.year()-2,1,1);
            Date dat4YearAgo = Date.newInstance( datToday.year()-4,1,1);
                
            // create & insert contact(s)
            Contact[] TestCons = UnitTestData.CreateMultipleTestContacts ( howMany ) ;
            insert TestCons;
            
            test.starttest();
            system.debug ( 'TEST>>>>> inserting gift 1...');
            
            // create a new gift for this yr
            Opportunity[] testGift1 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datToday, 100 , householdSettingsForTests.Membership_Record_Types__c,null);
            insert testGift1 ;
    
            system.debug ( 'TEST>>>>> inserting gift 2...');
            
            //create a 2nd gift for last yr
            Opportunity[] testGift2 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), dat1YearAgo, 60, householdSettingsForTests.Membership_Record_Types__c,null);
    
            insert testGift2;
            
            test.stopTest();
            
            //now test that the contact has received the proper stats from the trigger
            id ThisConId = TestCons[0].id;
            Contact UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c FROM Contact WHERE Id = :ThisConId];
            
            System.AssertEquals ( 160 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c );
            System.AssertEquals ( 60 , UpdatedCon.npo02__OppAmountLastYear__c );
    
            system.debug ( 'TEST>>>>> changing gift 1...');
            
            // now chg the amts for both opps (cheapskate!)
            testGift1[0].Amount = 50;
            update TestGift1;
    
            system.debug ( 'TEST>>>>> changing gift 2...');
            
            testGift2[0].Amount=25;
            update TestGift2;
            
            // now roll up manually
            OpportunityRollups rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
    
            ThisConId = TestCons[0].id;
            UpdatedCon = [SELECT Id, npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c  FROM Contact WHERE Id = :ThisConId];
            
            System.AssertEquals ( 75 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 50 , UpdatedCon.npo02__OppAmountThisYear__c );        
            System.AssertEquals ( 25 , UpdatedCon.npo02__OppAmountLastYear__c );
            
            system.debug ( 'TEST>>>>> inserting gift 3...');
    
            // now create a gift from 2 yrs ago
            Opportunity[] testGift3 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), dat2YearAgo, 10 , giftRecordTypeNameForTests,null);
    
            insert testGift3;
            
            // now roll up manually
            rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
    
            ThisConId = TestCons[0].id;
            UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
            
            System.AssertEquals ( 85 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 50 , UpdatedCon.npo02__OppAmountThisYear__c );        
            System.AssertEquals ( 25 , UpdatedCon.npo02__OppAmountLastYear__c );
            System.AssertEquals ( 10 , UpdatedCon.npo02__OppAmount2YearsAgo__c );
    
            // add another from this year (to test adding)
            system.debug ( 'TEST>>>>> inserting gift 4...');
            Opportunity[] testGift4 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datToday, 25 , giftRecordTypeNameForTests,null);
    
            insert testGift4;
            
            // now roll up manually
            rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
    
            UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
            
            System.AssertEquals ( 110 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 75 , UpdatedCon.npo02__OppAmountThisYear__c );        
            System.AssertEquals ( 25 , UpdatedCon.npo02__OppAmountLastYear__c );
            System.AssertEquals ( 10 , UpdatedCon.npo02__OppAmount2YearsAgo__c );
    
            // TBD add a gift from longer ago
            system.debug ( 'TEST>>>>> inserting gift 5...');
            Opportunity[] testGift5 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), dat4YearAgo, 200 , giftRecordTypeNameForTests,null);
    
            insert testGift5;
            
            // now roll up manually
            rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
            
            // totals should not have changed, except lifetime & best yr
            UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
            
            System.AssertEquals ( 310 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 75 , UpdatedCon.npo02__OppAmountThisYear__c );        
            System.AssertEquals ( 25 , UpdatedCon.npo02__OppAmountLastYear__c );
            System.AssertEquals ( 10 , UpdatedCon.npo02__OppAmount2YearsAgo__c );       
            
            // TBD add non-won gift
            system.debug ( 'TEST>>>>> inserting gift 6...');
            Opportunity[] testGift6 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getOpenStage(), dat4YearAgo, 35 , giftRecordTypeNameForTests,null);
    
            insert testGift6;
            
            // now roll up manually
            rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
            
            // totals should not have changed at all
            UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
            
            System.AssertEquals ( 310 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 75 , UpdatedCon.npo02__OppAmountThisYear__c );        
            System.AssertEquals ( 25 , UpdatedCon.npo02__OppAmountLastYear__c );
            System.AssertEquals ( 10 , UpdatedCon.npo02__OppAmount2YearsAgo__c );       
                    
            // now delete the 1st gift (now at $50), totals should decrease
            system.debug ( 'TEST>>>>> deleting gift 1...'); 
            delete testGift1;
            
            // now roll up manually
            rg = new OpportunityRollups();
            rg.rollupContact(testcons[0].id);
            
            UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
            
            System.AssertEquals ( 260 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 25 , UpdatedCon.npo02__OppAmountThisYear__c );        
            System.AssertEquals ( 25 , UpdatedCon.npo02__OppAmountLastYear__c );
            System.AssertEquals ( 10 , UpdatedCon.npo02__OppAmount2YearsAgo__c );               
            
            /*
            // finally add a larger gift from several yrs ago to test the best gift yr going earlier than other stats
            system.debug ( 'TEST>>>>> inserting gift 7...');
            Opportunity[] testGift7 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datToday.addYears(-5), 200 , 'Gift',null);
            ONEN_OpportunityContactRoles.haveCheckedContactRoles = false;
            insert testGift7;
    
            UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c, Best_Gift_Year__c, Best_Gift_Year_Total__c  FROM Contact WHERE Id = :ThisConId];
            System.AssertEquals ( datToday.addYears(-5).year() , UpdatedCon.Best_Gift_Year__c );
            System.AssertEquals ( 200 , UpdatedCon.Best_Gift_Year_Total__c );
            */      
        }
    }

    static testMethod void OneContactOneInkind() {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');

            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = 'In Kind',
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = 'In Kind',
                    Membership_Record_Types__c = null
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            integer howMany = 1;
            Date datToday = System.Today();
            
            // create & insert contact(s)
            Contact[] TestCons = UnitTestData.CreateMultipleTestContacts ( howMany ) ;
            insert TestCons;
            
            system.debug ( 'TEST>>>>> inserting gift 1...');
            
            // create a new gift for this yr
            Opportunity[] testGift1 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datToday, 100 , giftRecordTypeNameForTests,'In Kind');
            Test.StartTest();
            insert testGift1 ;
            Test.StopTest();
            
            id ThisConId = TestCons[0].id;
            contact UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
        
            System.Assert( !(UpdatedCon.npo02__TotalOppAmount__c>0) );
            
            //testGift1[0].Type = 'Cash';
            //update testGift1;
            
            //UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :ThisConId];
            //System.AssertEquals ( 100 , UpdatedCon.npo02__TotalOppAmount__c );
        
    
    }

    static testMethod void testGivingRollupBulk () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');
        
            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            // for a single contact w/ no previous mbrships, add a new membership
            // and test mbr stats are created
            integer howMany = 50;
            Date datClose = System.Today();
                
            // create & insert contact(s)
            Contact[] TestCons = UnitTestData.CreateMultipleTestContacts ( howMany ) ;
            insert TestCons;
            
            // create new opps
            Opportunity[] newOpps1 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose, 100 , giftRecordTypeNameForTests,null);
            Opportunity[] newOpps2 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose.addYears(-1), 50 , giftRecordTypeNameForTests,null);
    
            // insert the opp(s)
            Test.StartTest();
            insert newOpps1;
    
            insert newOpps2;
    
            Test.StopTest();
            
            id FirstConId = TestCons[10].id;
            Contact UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :FirstConId];
            
            System.AssertEquals ( 150 , UpdatedCon.npo02__TotalOppAmount__c );
            System.AssertEquals ( 100 , UpdatedCon.npo02__OppAmountThisYear__c );       
            System.AssertEquals ( 50 , UpdatedCon.npo02__OppAmountLastYear__c );
            System.AssertEquals ( 0 , UpdatedCon.npo02__OppAmount2YearsAgo__c );
        
    }

    static testMethod void testGivingRollupTooManyOpps () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');

            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            // for a single contact w/ no previous mbrships, add a new membership
            // and test mbr stats are created
        
            // create & insert contact(s)
            Contact[] TestCons = UnitTestData.CreateMultipleTestContacts ( 1 ) ;
            insert TestCons;
            
            // create new opps
            Opportunity[] newOpps1 = new Opportunity[0];
            for (integer n = 0; n < 450; n++) {
                Opportunity newOpp1 = new opportunity(npe01__Contact_Id_for_Role__c = TestCons[0].id,
                    name = 'test opp ' + n, 
                    stagename = UnitTestData.getClosedWonStage(), closedate = system.today().adddays(-n), amount = 100);
                if(areRecordTypesOnOpps()){
                    newOpp1.put('RecordTypeId',RecordTypes.GetRecordTypeId('Opportunity', giftRecordTypeNameForTests));
                }
                newOpps1.add( newOpp1);
            }
            
            // insert the opp(s)
            Test.StartTest();
            insert newOpps1;
            Test.StopTest();
            
            id FirstConId = TestCons[0].id;
            Contact UpdatedCon = [SELECT Id,  npo02__TotalOppAmount__c, npo02__OppAmountThisYear__c, npo02__OppAmountLastYear__c, npo02__OppAmount2YearsAgo__c FROM Contact WHERE Id = :FirstConId];
            
            System.AssertEquals ( 45000 , UpdatedCon.npo02__TotalOppAmount__c );
        
    } 
    
    static testMethod void testHouseholdStats () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');

            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            Date datClose = System.Today();
                
            // create & insert contact
            Contact Con1 = new contact(
                FirstName= npe01.Constants.CONTACT_FIRSTNAME_FOR_TESTS,
                LastName= npe01.Constants.CONTACT_LASTNAME_FOR_TESTS,
                npe01__Private__c=false,
                npe01__WorkEmail__c = npe01.Constants.CONTACT_EMAIL_FOR_TESTS, 
                npe01__Preferred_Email__c = npe01.Constants.CONTACT_PREFERRED_EMAIL_FOR_TESTS,
                npe01__WorkPhone__c = npe01.Constants.CONTACT_PHONE_FOR_TESTS,
                npe01__PreferredPhone__c = npe01.Constants.CONTACT_PREFERRED_PHONE_FOR_TESTS
            );
            insert Con1;
            
            Contact con = [SELECT npo02__household__r.id FROM Contact WHERE id = :Con1.id LIMIT 1];
            
            // create & insert second household member
            Contact Con2 = new contact(
                FirstName= npe01.Constants.CONTACT_FIRSTNAME_FOR_TESTS+'second',
                LastName= npe01.Constants.CONTACT_LASTNAME_FOR_TESTS,
                npe01__Private__c=false,
                npe01__WorkEmail__c = npe01.Constants.CONTACT_EMAIL_FOR_TESTS, 
                npe01__Preferred_Email__c = npe01.Constants.CONTACT_PREFERRED_EMAIL_FOR_TESTS,
                npe01__WorkPhone__c = npe01.Constants.CONTACT_PHONE_FOR_TESTS,
                npe01__PreferredPhone__c = npe01.Constants.CONTACT_PREFERRED_PHONE_FOR_TESTS,
                npo02__household__c = con.npo02__household__c
            );
            insert Con2;
            
            Contact[] TestCons = new Contact[] {Con1}; 
        
            // create new opps
            Opportunity[] newOpps1 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose, 100 , giftRecordTypeNameForTests ,null);
            Opportunity[] newOpps2 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose.addYears(-2), 200 , giftRecordTypeNameForTests ,null);
            Opportunity[] newOpps3 = UnitTestData.OppsForContactList ( TestCons, null, UnitTestData.getClosedWonStage(), datClose.addYears(-3), 75 , giftRecordTypeNameForTests ,null);
    
            Opportunity[] testOpps = new Opportunity[0];
            testOpps.addAll (newOpps1);
            testOpps.addAll (newOpps2);
            testOpps.addAll (newOpps3);
    
            // insert the opp(s)
            Test.StartTest();
            insert testOpps;
            Test.StopTest();
            
            Contact c = [SELECT Id,Total_Household_Gifts__c,OppAmountThisYearHH__c,OppAmountLastYearHH__c,LastCloseDateHH__c
                FROM Contact WHERE LastName=:npe01.Constants.CONTACT_LASTNAME_FOR_TESTS AND FirstName=:npe01.Constants.CONTACT_FIRSTNAME_FOR_TESTS+'second' LIMIT 1];
            System.assertEquals (375,c.Total_Household_Gifts__c);
            System.assertEquals (100,c.OppAmountThisYearHH__c);
            System.assertEquals (0,c.OppAmountLastYearHH__c);
            System.assertEquals (datClose,c.LastCloseDateHH__c );
            System.assertEquals (375,c.Total_Household_Gifts__c);
                
    }
    
        
    static testMethod void testUserDefinedRollup() {
        isTest = true;

        Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null
         ));
        npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
        ));
    
        //need to clear out any existing user fields
        //otherwise we can't insert of stuff referenced by apex
        list<User_Rollup_Field_Settings__c> deleteUserSettings = new list<User_Rollup_Field_Settings__c>();
        deleteUserSettings = [select id from User_Rollup_Field_Settings__c];
        delete deleteUserSettings;
        
        list<User_Rollup_Field_Settings__c> testURFS = new list<User_Rollup_Field_Settings__c>();
                
        User_Rollup_Field_Settings__c testUserRollup1 = new User_Rollup_Field_Settings__c();
        testUserRollup1.npo02__Target_Field__c = 'Birthdate'; 
        testUserRollup1.npo02__Source_Field__c = 'CloseDate';
        testUserRollup1.npo02__Object_Name__c = 'Contact'; 
        testUserRollup1.npo02__Field_Action__c = 'MAX';
        testUserRollup1.Name = 'TestRollup1';
        testURFS.add(TestUserRollup1);
        
        User_Rollup_Field_Settings__c TestUserRollup2 = new User_Rollup_Field_Settings__c();
        testUserRollup2.npo02__Target_Field__c = 'npo02__MembershipEndDate__c'; 
        testUserRollup2.npo02__Source_Field__c = 'CloseDate';
        testUserRollup2.npo02__Object_Name__c = 'Account'; 
        testUserRollup2.npo02__Field_Action__c = 'MAX';
        testUserRollup2.Name = 'TestRollup2';
        testURFS.add(TestUserRollup2);
        
        User_Rollup_Field_Settings__c testUserRollup3 = new User_Rollup_Field_Settings__c();
        testUserRollup3.npo02__Target_Field__c = 'npo02__LastCloseDate__c'; 
        testUserRollup3.npo02__Source_Field__c = 'CloseDate';
        testUserRollup3.npo02__Object_Name__c = 'npo02__Household__c'; 
        testUserRollup3.npo02__Field_Action__c = 'MAX';
        testUserRollup3.Name = 'TestRollup3';
        testURFS.add(TestUserRollup3);
        
        insert testURFS; 
        
        Contact c = new Contact(LastName = 'Lastname', BirthDate = system.today().addDays(-4));
        insert c;
        
        id rtid = RecordTypes.GetRecordTypeId ('Opportunity',RecordTypes.getRecordTypeNameForGiftsTests('Opportunity'));
        Opportunity newOpp = New Opportunity (
                Name = 'Test Opp ',
                Amount = 100,
                CloseDate = system.today().adddays(-2),
                StageName = UnitTestData.getClosedWonStage(),
                npe01__Contact_Id_for_Role__c = c.Id                                
            );  
            if(rtid != null){
                newOpp.put('RecordTypeId',rtid);
            }
         
    Test.StartTest();
    insert newOpp;
    Test.StopTest();     
    
    Contact ct = [select Birthdate, OppAmountThisYearHH__c from Contact where id = :c.id];
    system.assertEquals (100,ct.OppAmountThisYearHH__c);    
    system.assertEquals(system.today().addDays(-2), ct.BirthDate);    
    
    }
    
    static testMethod void testMultiCurrencyMethods(){
        
        //exercise internal multicurrency helper methods, check currency conversion             
        decimal d = OpportunityRollups.ConvertFromCorporate('USD', 55.00);      
        d = OpportunityRollups.ConvertCurrency('USD', 'USD', 55.00);


        //create & insert second household member
        Contact Con = new contact(
                FirstName= npe01.Constants.CONTACT_FIRSTNAME_FOR_TESTS,
                LastName= npe01.Constants.CONTACT_LASTNAME_FOR_TESTS,
                npe01__Private__c=false,
                npe01__WorkEmail__c = npe01.Constants.CONTACT_EMAIL_FOR_TESTS, 
                npe01__Preferred_Email__c = npe01.Constants.CONTACT_PREFERRED_EMAIL_FOR_TESTS,
                npe01__WorkPhone__c = npe01.Constants.CONTACT_PHONE_FOR_TESTS,
                npe01__PreferredPhone__c = npe01.Constants.CONTACT_PREFERRED_PHONE_FOR_TESTS                
            );
            insert Con;
            
        Contact[] TestCons = new Contact[] {Con}; 
        
        // create new opps
        Opportunity o = new Opportunity(
            Name = 'MyContactOpportunity',
            StageName = 'Closed Won',
            CloseDate = system.today(),
            npe01__Contact_Id_for_Role__c = con.Id  
        );        
        insert o;
        
        list<sobject> sobjectlist = new list<sobject>();
        //sobjectlist.add(o); 
        
        OpportunityRollups opproll = new OpportunityRollups();
        map<Id, Opportunity> omap = opproll.rcfFindCurrency(sobjectList);
    }
    static testMethod void testRollupAlls(){
        OpportunityRollups og = new OpportunityRollups();
        
        test.startTest();
        og.rollupAllContacts();
        og.rollupAllAccounts();     
        boolean x = OpportunityRollups.isMultiCurrency();
        decimal y = OpportunityRollups.ConvertFromCorporate('USD', 500.00);
        decimal z = OpportunityRollups.ConvertCurrency('USD', 'USD', 6565.54);
        test.stopTest();
    }
    static testMethod void testFiscalYearandCustomNDay () {
        isTest = true;
        String giftRecordTypeNameForTests = RecordTypes.getRecordTypeNameForGiftsTests('Opportunity');

            Households_Settings__c householdSettingsForTests = Households.getHouseholdsSettingsForTests(
                new Households_Settings__c (
                    Household_Rules__c = Households.ALL_PROCESSOR,
                    Always_Rollup_to_Primary_Contact__c = false,
                    Enable_Opp_Rollup_Triggers__c = true,
                    Excluded_Account_Opp_Rectypes__c = null,
                    Excluded_Account_Opp_Types__c = null,
                    Excluded_Contact_Opp_Rectypes__c = null,
                    Excluded_Contact_Opp_Types__c = null,
                    Membership_Record_Types__c = null,                     
                    Use_Fiscal_Year_for_Rollups__c = true, 
                    Rollup_N_Day_Value__c = 10
                ));
                
            npe01__Contacts_and_Orgs_Settings__c contactSettingsForTests = npe01.Constants.getContactsSettingsForTests(new npe01__Contacts_and_Orgs_Settings__c (
                npe01__Account_Processor__c = npe01.Constants.ONE_TO_ONE_PROCESSOR,
                npe01__Enable_Opportunity_Contact_Role_Trigger__c = true,
                npe01__Opportunity_Contact_Role_Default_role__c = 'Donor'
            ));
            
            // for a single contact w/ no previous mbrships, add a new membership
            // and test mbr stats are created
        
            // create & insert contact(s)
            Contact[] TestCons = UnitTestData.CreateMultipleTestContacts ( 1 ) ;
            insert TestCons;
            
            // create 2 new opps
            Opportunity[] newOpps1 = new Opportunity[0];
            
            Opportunity newOpp1 = new opportunity(npe01__Contact_Id_for_Role__c = TestCons[0].id,
                    name = 'test opp ', 
                    stagename = UnitTestData.getClosedWonStage(), closedate = system.today(), amount = 100);
               if(areRecordTypesOnOpps())
                    newOpp1.put('RecordTypeId',RecordTypes.GetRecordTypeId('Opportunity', giftRecordTypeNameForTests));
            newOpps1.add( newOpp1);
            
            Opportunity newOpp2 = new opportunity(npe01__Contact_Id_for_Role__c = TestCons[0].id,
                    name = 'test opp 2', 
                    stagename = UnitTestData.getClosedWonStage(), closedate = system.today().adddays(-40), amount = 100);
               if(areRecordTypesOnOpps())
                    newOpp2.put('RecordTypeId',RecordTypes.GetRecordTypeId('Opportunity', giftRecordTypeNameForTests));
            newOpps1.add(newOpp2);
           
            // insert the opp(s)
            Test.StartTest();
            insert newOpps1;
            Test.StopTest();
    
            system.assertEquals([select OppAmountLastNDays__c from Contact where id = :TestCons[0].id].OppAmountLastNDays__c, 100);
    }
}