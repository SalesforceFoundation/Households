//set of utility methods and values used in opportunity rollups

public without sharing class OpportunityRollup_Utilities {

    /*** Settings ***/	     
    public static boolean useFiscalYear = false;
    public static set<id> recordTypesToExcludeAccts = new set<id>();
    public static set<id> recordTypesToExcludeCons = new set<id>();
    public static set<id> mbrRecordTypes = new set<id>(); 
    public static set<string> oppTypesToExcludeAccts = new set<string>();
    public static set<string> oppTypesToExcludeCons = new set<string>();  
    public static Households_Settings__c hh_settings;
    public static boolean recordTypesOnOpps = false;
    
    /*** Multicurrency ***/
    //set when multicurrency check is called, holds the field string/sobject mapping
    public static Map<String, SObjectField> mcFieldValues = new Map<String, SObjectField>();
    public static boolean multiCurrency;
    //exchangerate store
    static map<string, decimal> exchangeRates = new map<string,decimal>();
    //corporate currency
    static string currCorporate; 
    
    /*** User Rollups ***/
    //map of object and rollup field 
    public static map<string, string> objectRollUpFieldMap = new map<string, string>();
    public static map<string, User_Rollup_Field_Settings__c> urfsMap = new map<string, User_Rollup_Field_Settings__c>();
    
    /*** Query Building ***/
    
    

    /*** Settings Methods ***/ 
    //configures and sets up static vars for OppRollups
    public static void setupRollupVars(Households_Settings__c household_settings){
        
        if (household_settings.Excluded_Contact_Opp_Rectypes__c != null) {
            set<string> rtNamesToExclude = new set<string>(household_settings.Excluded_Contact_Opp_Rectypes__c.split(';'));
            recordTypesToExcludeCons = RecordTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
        }
        if (household_settings.Excluded_Account_Opp_Rectypes__c != null) {
            set<string> rtNamesToExclude = new set<string>(household_settings.Excluded_Account_Opp_Rectypes__c.split(';'));
            recordTypesToExcludeAccts = RecordTypes.GetRecordTypeIdSet('Opportunity', rtNamesToExclude);
        }
        if (household_settings.Excluded_Contact_Opp_Types__c != null) {
            oppTypesToExcludeCons = new set<string>(household_settings.Excluded_Contact_Opp_Types__c.split(';'));
        }
        if (household_settings.Excluded_Account_Opp_Types__c != null) {
            oppTypesToExcludeAccts = new set<string>(household_settings.Excluded_Account_Opp_Types__c.split(';'));
        }    
        if (household_settings.Membership_Record_Types__c != null) {
            set<string> mbrRecordTypeNames = new set<string>(household_settings.Membership_Record_Types__c.split(';'));
            mbrRecordTypes = RecordTypes.GetRecordTypeIdSet('Opportunity', mbrRecordTypeNames);
        }  
        
        //check the settings, if they have the fiscal year set
        //we still need to query to make sure its not a custom fiscal year
        //or else we'll throw errors when calling Fiscal_Year in queries
        if (household_settings.npo02__Use_Fiscal_Year_for_Rollups__c == true){
            integer hasCustomFYRecord = [select count() from FiscalYearSettings];
                
            //if org has customFY records, disable FY settings
            if (hasCustomFYRecord > 0 && !household_settings.Force_Fiscal_Year__c)
                useFiscalYear = false;
            else
                useFiscalYear = true;
        }        
        //set the static var
        hh_settings = household_settings;
    }        
    
    
    public static void setupUserRollupVars(){
        urfsMap = User_Rollup_Field_Settings__c.getAll().clone();
        //build the object delineated query string for use later
        for (string s : urfsMap.keySet()){
        	User_Rollup_Field_Settings__c urfs = urfsMap.get(s);
        	
        	if (objectRollUpFieldMap.containsKey(urfs.Object_Name__c)){
        		String qString = objectRollupFieldMap.get(urfs.Object_Name__c);
        		qString += urfs.Field_Action__c + '(Opportunity.' + urfs.Source_Field__c + ') ' + urfs.Name + ', ';
        		objectRollupFieldMap.put(urfs.Object_Name__c, qString);
        	}
        	else{
        		objectRollupFieldMap.put(urfs.Object_Name__c, urfs.Field_Action__c + '(Opportunity.' + urfs.Source_Field__c + ') ' + urfs.Name + ', ');
        	}
        }	
    }
	
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
    /****************************************/
	
	
    /*** Multicurrency Support Methods ***/
    
    //returns a boolean if we are in a multi-currency org or not.
    //on first execution sets up static variables etc
    public static boolean isMultiCurrency(){                    
        if (multiCurrency==null){
            //create currency field handles for later dynamic dml
            mcFieldValues.put('Opportunity', Schema.sObjectType.Opportunity.fields.getMap().get('CurrencyIsoCode'));
            mcFieldValues.put('Account', Schema.sObjectType.Account.fields.getMap().get('CurrencyIsoCode'));
            mcFieldValues.put('Contact', Schema.sObjectType.Contact.fields.getMap().get('CurrencyIsoCode'));
            mcFieldValues.put('npo02__Household__c', Schema.sObjectType.npo02__Household__c.fields.getMap().get('CurrencyIsoCode'));

            String queryExchangeRates = 'select IsoCode,ConversionRate,IsCorporate from CurrencyType';
            SObjectType soCurrencyType = Schema.getGlobalDescribe().get('CurrencyType'); 

            //are we in a multi-currency org?
            if (mcFieldValues.get('Opportunity') != null && mcFieldValues.get('Account') != null && 
                mcFieldValues.get('npo02__Household__c') != null && mcFieldValues.get('Contact') != null && soCurrencyType != null){
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
    public static decimal convertFromCorporate(String ISO,Decimal amt){
        if(currCorporate == ISO || currCorporate == null) // no need to convert
            return amt;
        else //return value to 2DP
            return (amt * exchangeRates.get(ISO)).setScale(2) ;
    }

    public static decimal convertCurrency(String fromISO, String toISO, Decimal amt){
        if(fromISO == toISO) // no need to convert
            return amt;
        else //return value to 2DP
            return ((amt / exchangeRates.get(fromISO)) * exchangeRates.get(toISO)).setScale(2) ;
    }
 
    //takes the Ids of opptys in the npo02__CombinedRollupFieldset__c field, and looks up the currency of that record
    //only used in multi currency orgs
    //returns a map of those Ids and the associated oppty
    public static map<Id,Opportunity> rcfFindCurrency(list<sobject> objectList){
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
    /****************************************/
    
    /*** Opportunity Evaluation Methods ***/
    //evaluates a single Opportunity to see if it needs to be rolled up    
    public static boolean oppForRollup(Opportunity o){
    	boolean needsRollup = false;
    	if (o.isWon && o.Amount != null)
    	   needsRollup = true;
    	return needsRollup;
    }
    //evaluates if an Opp will need a contact-based rollup
    public static boolean needsContactRollup(Opportunity o){
    	boolean needsRollup = false;
    	//if its from an individual account or has a null account ID OR alwaysRollupToPrimary is set AND
    	//its the membership rectype or the rectype isn't exclused AND
    	//the opp type isn't excluded    	 
        if (((o.npe01__Is_Opp_From_Individual__c == 'true' || o.accountid == null) || hh_settings.Always_Rollup_to_Primary_Contact__c) &&
                (mbrRecordTypes.contains((id)o.get('recordTypeId')) || !recordTypesToExcludeCons.contains((id)o.get('recordTypeId'))) &&
                (!oppTypesToExcludeCons.contains(o.type))){
            needsRollup = true;
        }
    	return needsRollup;
    }
    //evaluates if an Opp belongs to a valid Account needing a rollup
    public static boolean needsAccountRollup(Opportunity o){
        boolean needsRollup = false;    
    	//if the account id is not null and its not the individual/bucket account AND
    	//its the membership rectype or the rectype isn't exclused AND
        //the opp type isn't excluded
    	if (o.AccountId != null && o.AccountId != npe01.Constants.GetIndividualAccountId() && 
    	(mbrRecordTypes.contains((id)o.get('recordTypeId')) || !recordTypesToExcludeAccts.contains((id)o.get('recordTypeId'))) && 
    	!oppTypesToExcludeAccts.contains(o.type)){
            needsRollup = true;    	           
    	}                                    
    	return needsRollup;
    }
    //evaluates two opps for changes that would require a rollup
    public static boolean oppForRollup (Opportunity newOpp, Opportunity oldOpp){
        boolean needsRollup = false;    	  
        //if the iswon stage has changed, or its iswon and the amount has changed
        //or the recordtype has changed, or the type has changed, or the account id has changed
        //or its won and any of the membership fields have changed
        if (newOpp.isWon != oldOpp.isWon ||
            (newOpp.isWon && (newOpp.Amount != oldOpp.Amount)) ||
            (id)newOpp.get('recordTypeId') != (id)oldOpp.get('recordTypeId') ||                                            
            newOpp.type != oldOpp.type ||
            newOpp.closeDate != oldOpp.closeDate ||
            newOpp.accountId != oldOpp.accountId ||
            (newOpp.isWon && (newOpp.npe01__Membership_Start_Date__c != oldOpp.npe01__Membership_Start_Date__c || 
                              newOpp.npe01__Membership_End_Date__c != oldOpp.npe01__Membership_End_Date__c ||                                            
                              newOpp.npe01__Member_Level__c != oldOpp.npe01__Member_Level__c))){
            needsRollup = true;                              	     
        }        
        return needsRollup;
    }    
    
    /****************************************/
    
    

}