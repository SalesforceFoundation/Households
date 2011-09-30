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
trigger HouseholdAfter on Household__c (after update) {

    Households_Settings__c hs = Households.getHouseholdsSettings();
    
    if (!hs.DISABLE_HouseholdAfter_trigger__c){
    
        //sends household names to be updated if 
        if (!HouseholdProcessControl.inFutureContext && trigger.isAfter){
            if (hs != null && hs.Advanced_Household_Naming__c == true){
            
                list<id> hhlist = new list<id>();
                
                for (Household__c h : trigger.new){
                    if(h.Name == system.Label.NameReplacementText)
                       hhlist.add(h.id);
                    else if (h.Informal_Greeting__c == system.Label.NameReplacementText)
                       hhlist.add(h.id);
                    else if (h.Formal_Greeting__c == system.Label.NameReplacementText)
                        hhlist.add(h.id);       
                    else if (h.SYSTEM_CUSTOM_NAMING__c != trigger.oldmap.get(h.id).SYSTEM_CUSTOM_NAMING__c)
                        hhlist.add(h.id);
                }
    
               if (!hhlist.isEmpty()){
                    Householdnaming hn = new HouseholdNaming();
                    hn.UpdateNames(hhlist);
                }
            }
        }
    }
}