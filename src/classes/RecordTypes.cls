/**
* @author Evan Callahan
* @date 2010 
* @description Provides recordtype wrapper for easy access in other codeblocks 
*/

global class RecordTypes {
    global static String giftRecordTypeNameForTests;
    global static String membershipRecordTypeNameForTests;            
    global static Id GetRecordTypeId(String objectName, String RecordTypeName) {return null;}
    global static string getRecordTypeNameForGiftsTests(String objectName){return null;}
    global static string getRecordTypeNameForMembershipTests(String objectName){return null;}
    global static String GetRecordTypeName(String objectName, Id RecordTypeId) {return null;}
    global static set<Id> GetRecordTypeIdSet(String objectName, set<string> RecordTypeNameSet) {return null;}
    global static Map<String, Id> GetRecordTypeIdMap(String objectName) {return null;}
    global static String GetOppNamingSuffix(String RecordTypeName){return null;}
    global static List<SelectOption> getRecordTypesForSelectList(String objectName) {return null;}
    global static List<SelectOption> getStringRecordTypesForSelectList(String objectName) {return null;}
    
    static testmethod void test() {
    	RecordTypes.GetRecordTypeId(null, null);
    	RecordTypes.getRecordTypeNameForGiftsTests(null);
    	RecordTypes.getRecordTypeNameForMembershipTests(null);
    	RecordTypes.GetRecordTypeName(null, null);
    	RecordTypes.GetRecordTypeIdSet(null, null);
    	RecordTypes.GetRecordTypeIdMap(null);
    	RecordTypes.GetOppNamingSuffix(null);
    	RecordTypes.getRecordTypesForSelectList(null);
    	RecordTypes.getStringRecordTypesForSelectList(null);
    }
}