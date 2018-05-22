*! Ver 1.0.2 23may2018 Simone Signore
*! Stata API client for db.nomics.world. Requires libjson and moss
capture program drop dbnomics

/* Main wrapper command */
program dbnomics, rclass
	
	/* May need adjustment because of https*/
	version 14.0			
	
	/* Changelog
	20mar2018  v1.0.0 Initial release
	08may2018  v1.0.1 Fixed syntax parsing bug
	23may2018  v1.0.2 Updated to API ver 0.18.0
	*/
	
	/*TODO:
	Refine series parser to capture additional panel objects
	Integrate dataset search endpoint?
	*/

	/* Housekeeping: taken from insheetjson */
	/* Check if libjson exists */
	mata: if (findexternal("libjson()")) {} else printf("{err:Error: The required JSON library (libjson) seems to be missing so this command will fail. Read the help file for more information.}\n");

	/* Check libjson version */
	mata: if (libjson::checkVersion((1,0,2))) {} else printf("{err: The JSON library version is not compatible with this command and so will likely fail. Please update libjson.}\n");
	
	/* Check whether moss is installed */
	capture which moss
	if _rc {
		di as smcl `"{err:Error: the package {cmd:moss} is required by {cmd:dbnomics}. Try {stata "ssc install moss":ssc install moss}}"'
		exit 111
	}

	syntax [anything(name=subcall id="subcall list")], [CLEAR *]

	/* Setup API endpoint */
	local apipath = "https://api.next.nomics.world" /* https://api.db.nomics.world/api/v1/json */
	
	/* Parse subcall*/
	if inlist("`subcall'","provider","providers") {
		dbnomics_providers `apipath', `clear'
	}
	else if "`subcall'" == "tree" {
		dbnomics_tree `apipath', `clear' `macval(options)'
	}
	else if inlist("`subcall'","data","datastructure") {
		dbnomics_structure `apipath', `clear' `macval(options)'
	}
	else if "`subcall'" == "series" {
		dbnomics_series `apipath', `clear' `macval(options)'
	}
	else if "`subcall'" == "import" {
		dbnomics_import `apipath', `clear' `macval(options)'
	}
	else if (substr("`subcall'",1,4) == "use ") {
		tokenize `macval(subcall)'
		dbnomics_use `2', `clear' `macval(options)' path(`apipath')
	}	
	else {
		di as err "dbnomics: unknown subcommand "`""`subcall'""'"" 
		exit 198
	}

	return local endpoint "`subcall'"
	
	/* Housekeeping */
	mata: mata clear	

end

/*Subroutines*/
/*1) Providers table */
program dbnomics_providers
	
	syntax anything(name=path), [CLEAR]
	
	/* Setup call*/
	local apipath = "`path'"
	
	/* Parse clear option*/
	if ("`clear'" == "") {
		if `c(width)' > 0 {
			di as err "no; data in memory would be lost. Use the {cmd:clear} option"
			exit 4
		}
	} 
	else {
		clear
	}
	
	display as txt "Downloading list of providers..."
	
	/* Save json locally to reduce server load over multiple calls */
	tempfile jdata
	capture copy "`apipath'" `jdata', replace
	if (inrange(_rc,630,696) | _rc == 601) {
		if (_rc == 601) di as err "Network error. Invalid API endpoint."
		exit _rc
	}
	else if (_rc > 0) {
		di as err "Kernel panic. Abort"
		exit _rc
	}
	
	/* Parse JSON */
	mata: providers = fetchjson("`jdata'", "");
	mata: provobj = fetchjson("`jdata'", "providers");
	mata: provnode = provobj->getNode("docs");
	
	/* Check for error in response */
	mata: parseresperr(providers);
	
	/* Parse metadata */
	mata: st_local("nomicsmeta", parsemeta(providers));
	
	/* Call mata function */
	mata: pushdata(json2table(provnode), jsoncolsArray(provnode, 0)');
	
	/* Reduce space (this can be automated in the future)*/
	qui compress	
	
	/* Housekeeping */
	quietly {
		cleanutf8
		destring _all, replace
		remove_destrchar _all
		auto_labels _all
	}	
	
	capture order code name region, first
	
	/* Add metadata as dataset data characteristic */
	char _dta[endpoint] "`apipath'"
	char _dta[_meta] "`nomicsmeta'"
	
end

/*2) Dataset trees */
program dbnomics_tree

	syntax anything(name=path), PRovider(string) [KEYS(string) CLEAR LEVel(name)]
	
	/* Setup call*/
	local apipath = "`path'/`provider'"
	
	/* Parse clear option*/
	if ("`clear'" == "") {
		if `c(width)' > 0 {
			di as err "no; data in memory would be lost. Use {cmd:clear} option"
			exit 4
		}
	} 
	else {
		clear
	}	
	
	/* Save json locally to reduce server load over multiple calls */
	tempfile jdata
	capture copy "`apipath'" `jdata', replace
	if (inrange(_rc,630,696) | _rc == 601) {
		if (_rc == 601) di as smcl "{err:Network error. Please ensure {cmd:`provider'} is a valid DB.nomics provider}"
		exit _rc
	}
	else if (_rc > 0) {
		di as err "Kernel panic. Abort"
		exit _rc
	}	
	else {
		display as txt "Downloading category tree for `provider'..."
	}	

	/* Parse JSON */
	mata: tree = fetchjson("`jdata'", "");
	
	/* Check for error in response */
	mata: parseresperr(tree);
	
	/* Parse metadata */
	mata: st_local("nomicsmeta", parsemeta(tree));	
	
	/* Call mata function */
	tempname lvl
	mata: pushdata(parsetree(tree, treekeys("`keys'")), ("`lvl'", treekeys("`keys'")));
	
	/* Reduce space (this can be automated in the future)*/
	qui compress	
	
	/* Parse level */
	tempvar lvlenc lvlgroup
	quietly {
		gen `lvlenc' = real(`lvl')
		if ("`level'" != "") {
			confirm new variable `level'
			egen `level' = group(`lvlenc')
			lab var `level' "Level"
			order `level'
		}
		else {
			confirm new variable level
			egen level = group(`lvlenc')
			lab var level "Level"
			order level
		}
	}
	
	/* Housekeeping */
	quietly {
		cleanutf8
		auto_labels _all
	}
	
	/* Add provider metadata */
	mata: metadata = ("website","terms_of_use","region","name");
	mata: providermeta = fetchkeyvals(fetchjson("`jdata'", "provider"), metadata);
	mata: for (kk=1; kk<=cols(metadata); kk++) st_lchar("_dta", metadata[kk], providermeta[kk]);

	/* Add metadata as dataset data characteristic */
	char _dta[provider] "`provider'"
	char _dta[endpoint] "`apipath'"	
	char _dta[_meta] "`nomicsmeta'"
	
end

/*3) Datastructure */
program dbnomics_structure
	
	syntax anything(name=path), PRovider(string) Dataset(string) [CLEAR noSTAT]
	
	/* Setup call*/
	local apipath = "`path'/`provider'/`dataset'/series?limit=0&offset=0"
	
	/* Parse clear option*/
	if ("`clear'" == "") {
		if `c(width)' > 0 {
			di as err "no; data in memory would be lost. Use {cmd:clear} option"
			exit 4
		}
	} 
	else {
		clear
	}		
	
	/* Save json locally to reduce server load over multiple calls */
	tempfile jdata
	capture copy "`apipath'" `jdata', replace
	if (inrange(_rc,630,696) | _rc == 601) {
		if (_rc == 601) di as smcl "{err:Network error. Please ensure that {cmd:`provider'} and {cmd:`dataset'} are valid DB.nomics endpointts}"
		exit _rc
	}
	else if (_rc > 0) {
		di as err "Kernel panic. Abort"
		exit _rc
	}	

	/* Parse JSON */
	mata: structure = fetchjson("`jdata'", "");
	
	/* Check for error in response */
	mata: parseresperr(structure);
	
	/* Parse metadata */
	mata: st_local("nomicsmeta", parsemeta(structure));

	/* Parse dataset structure */
	mata: datainfo = fetchjson("`jdata'", "dataset");
	mata: datastruct = datainfo->getNode("dimensions_values_labels");
	/* Check whether null structure */
	mata: st_local("nullstruct", strofreal(datastruct==NULL));
	
	/* Proceed accordingly */
	if ("`nullstruct'" == "0") {
	
		mata: tablestruct = dict2table(datastruct, dictdim(datastruct)[.,2]);
		mata: pushdata(tablestruct, tokenizer("dimensions_values_labels", "_"));
		
		/* Add additional statistics (default) */
		if "`stat'" == "" {
			
			/* Select facets node */
			mata: statstruct = structure->getNode("series_dimensions_facets");
			
			/* Series stats matrix */
			local nofacets 0
			mata: tablesstat = dict2table(statstruct, dictdim(statstruct)[.,2]);
			
			/* Capture empty node */
			mata: st_local("nofacets", strofreal(tablesstat == "0"));
			
			if (`nofacets' == 0) {
			
				tempfile statdata
				preserve
				
					drop _all
						
					/* Keep only additional data */
					mata: tablesstat = select(tablesstat, tablesstat[.,cols(tablesstat)-1] :== "count");
					
					/* Keep even cols */
					mata: tablesstat = select(tablesstat, J(1, ceil(cols(tablesstat)/2), (1,0))[.,1..cols(tablesstat)]);
					mata: pushdata(tablesstat, tokenizer("dimensions_values_seriesnr", "_"));
				
					qui save `statdata'
				restore
				
				qui merge 1:1 dimensions values using `statdata', keep(1 3) nogen norep
			
			}
			
		}
		
		/* Reduce space (this can be automated in the future)*/
		qui compress		

		/* Housekeeping */
		quietly {
			cleanutf8
			/* Use destring carefully */
			unab nodestr: dimensions values
			unab allvars : _all
			local todestr : list allvars - nodestr
			destring `todestr', replace
			remove_destrchar _all
			auto_labels _all
		}
	}
	else {
		di as smcl "{err:Warning. Dataset structure not found for {cmd:`dataset'}}"
	}
	
	/* Add provider metadata */
	mata: metadata = ("nb_series","code","name");
	mata: datafeat = fetchkeyvals(datainfo, metadata);
	mata: for (kk=1; kk<=cols(metadata); kk++) st_lchar("_dta", metadata[kk], datafeat[kk]);
	
	/* Finally get datastructure template */
	mata: structinfo = parsestructure(datainfo);
	mata: st_local("dtstructure", structinfo);
	mata: st_lchar("_dta", "dtstructure", structinfo);
	
	local seriesnum : char _dta[nb_series1]
	display as res "`: char _dta[name1]' `: char _dta[name2]'"
	display as txt "`seriesnum' series found. Order of dimensions: (`dtstructure')"
	
	/* Add metadata as dataset data characteristic */
	char _dta[provider] "`provider'"
	char _dta[dataset] "`dataset'"
	char _dta[endpoint] "`apipath'"
	char _dta[_meta] "`nomicsmeta'"
	
end

/*4. Series */
program dbnomics_series
	
	syntax anything(name=path), PRovider(string) Dataset(string) [LIMIT(integer 300) OFFSET(integer 0) CLEAR *]  /*SDMX(string asis)*/

	/* smdx and dimensions mutually exclusive */
	/*if ("`sdmx'" != "" & "`macval(options)'" != "") {
		di as smcl "{err:Options {cmd:sdmx} and {cmd:dimensions} are mutually exclusive.}"
		exit 4
	}*/
	
	/* Parse filtering options */
	_optdict `macval(options)'
	if (`"`dimdict'"' != "") local thequery "&dimensions=`dimdict'"	
	
	/* if (`"`sdmx'"' != "") local thequery "&sdmx_filter=`sdmx'" */
	
	/* Parse clear option*/
	if ("`clear'" == "") {
		if `c(width)' > 0 {
			di as err "no; data in memory would be lost. Use {cmd:clear} option"
			exit 4
		}
	} 
	else {
		clear
	}		
	
	/* Capture limit override */
	local override 0
	if (`limit' != 300) local override 1
	
	/* Setup call*/
	local apipath = "`path'/`provider'/`dataset'/series?limit=`limit'&offset=`offset'`thequery'"
	
	/* Save json locally to reduce server load over multiple calls */
	tempfile jdata
	capture copy "`apipath'" `jdata', replace
	if (inrange(_rc,630,696) | _rc == 601) {
		if (_rc == 601) di as smcl "{err:Network error. Please ensure that {cmd:`provider'} and {cmd:`dataset'} are valid DB.nomics endpointts}"
		exit _rc
	}
	else if (_rc > 0) {
		di as err "Kernel panic. Abort"
		exit _rc
	}

	/* Parse JSON */
	mata: structure = fetchjson("`jdata'", "");
	
	/* Check for error in response */
	mata: parseresperr(structure);
	
	/* Parse metadata */
	mata: st_local("nomicsmeta", parsemeta(structure));

	/* Parse dataset structure */
	mata: datainfo = fetchjson("`jdata'", "dataset");
	
	/* Tot. series num. */
	mata: numseries = fetchkeyvals(datainfo, ("nb_series"));
	mata: st_local("series_count", numseries[1]);

	/* Parse series node */
	mata: seriesinfo = fetchjson("`jdata'", "series");

	/* Found series num */
	mata: fndseries = fetchkeyvals(seriesinfo, ("num_found"));
	mata: st_local("num_found", fndseries[1]);
	
	if (`limit' < min(`series_count',`num_found')) {
		if `override' {
			display as smcl "{err:Warning: series set not complete. Consider removing the {cmd:limit} option.}"
		}
		else {
			local newlimit = min(`series_count',`num_found')
			if (`newlimit' > 10000) display as smcl "{err:Warning: Dowload size is significant, so the command may take a while. Consider adding selection criteria or using the {cmd:limit} option.}"
			dbnomics_series `path', pr(`provider') d(`dataset') limit(`newlimit') offset(`offset') `clear' `macval(options)'
			exit 0
		}
	}
		
	/* Parse series list */
	mata: seriesdata = seriesinfo->getNode("docs");
	capture mata: pushdata(json2table(seriesdata), jsoncolsArray(seriesdata, 0)');
	
	if (_rc > 0) {
		display as smcl "{err:Warning: no series found.}"
	}
	else {
		/* Reduce space (this can be automated in the future)*/
		qui compress		

		/* Housekeeping */
		quietly {
			cleanutf8
			destring _all, replace
			remove_destrchar _all
			auto_labels _all
		}
	}
	
	/* Add provider metadata */
	mata: metadata = ("nb_series","code","name");
	mata: datafeat = fetchkeyvals(datainfo, metadata);
	mata: for (kk=1; kk<=cols(metadata); kk++) st_lchar("_dta", metadata[kk], datafeat[kk]);
	
	/* Finally get datastructure template */
	mata: structinfo = parsestructure(datainfo);
	mata: st_local("dtstructure", structinfo);
	mata: st_lchar("_dta", "dtstructure", structinfo);
	
	/* Display result */
	if (`"`thequery'"' != "") local series_parsed "`num_found' of "
	
	display as txt "`series_parsed'`series_count' series selected. Order of dimensions: (`dtstructure')" _c
	if (`override' & `limit' < min(`series_count',`num_found')) {
		display as txt ". Only first `limit' retrieved"
	}
	else {
		display as txt ""
	}
	
	/* Add metadata as dataset data characteristic */
	char _dta[provider] "`provider'"
	char _dta[dataset] "`dataset'"
	char _dta[endpoint] "`apipath'"
	char _dta[_meta] "`nomicsmeta'"
	
end

/*5. Import one or more series */
program dbnomics_import

	syntax anything(name=path), PRovider(string) Dataset(string) [LIMIT(integer 500) OFFSET(integer 0) SDMX(string asis) SERIESids(string asis) CLEAR *]
	
	/* smdx and dimensions mutually exclusive */
	if ("`sdmx'" != "" & "`macval(options)'" != "") {
		di as smcl "{err:Options {cmd:sdmx} and {cmd:dimensions} are mutually exclusive.}"
		exit 198
	}
	/* seriesids and dimensions mutually exclusive */
	if ("`seriesids'" != "" & "`macval(options)'" != "") {
		di as smcl "{err:Options {cmd:sdmx} and {cmd:dimensions} are mutually exclusive.}"
		exit 198
	}	
	/* seriesids and sdmx mutually exclusive */
	if ("`seriesids'" != "" & "`sdmx'" != "") {
		di as smcl "{err:Options {cmd:sdmx} and {cmd:seriesids} are mutually exclusive.}"
		exit 198
	}
	
	/* Parse filtering options */
	_optdict `macval(options)'
	if (`"`dimdict'"' != "") local thequery "&dimensions=`dimdict'"	
	if (`"`sdmx'"' != "") local thequery "&sdmx_filter=`sdmx'"

	/* Parse list of series (must be comma separated)*/
	if (`"`seriesids'"' != "") {
		local thequery "series_ids="
		gettoken series oseries : seriesids, parse(",")
		while ("`series'" != "") {
			if ("`series'" != ",") local thequery "`thequery'`provider'/`dataset'/`series',"
			gettoken series oseries : oseries, parse(",")
		}
		local thequery = substr(`"`thequery'"', 1, length(`"`thequery'"')-1)
	}
	
	/* Parse clear option*/
	if ("`clear'" == "") {
		if `c(width)' > 0 {
			di as err "no; data in memory would be lost. Use {cmd:clear} option"
			exit 4
		}
	} 
	else {
		clear
	}
	
	/* Capture limit override */
	local override 0
	if (`limit' != 500) local override 1
	
	/* Setup call*/
	if (`"`seriesids'"' != "") {
		local apipath = "`path'/series?`thequery'&limit=`limit'&offset=`offset'"
	}
	else {
		local apipath = "`path'/series?provider_code=`provider'&dataset_code=`dataset'&limit=`limit'&offset=`offset'`thequery'"	
	}
	
	/* ma li _apipath */
	
	/* Save json locally to reduce server load over multiple calls */
	tempfile jdata
	capture copy "`apipath'" `jdata', replace
	
	if (_rc == 672 & `"`sdmx'"' != "") {
		di as smcl "{err:Provider `provider' is not compatible with SDMX filters}"
		exit 198
	}
	else if (inrange(_rc,630,696) | _rc == 601) {
		if (_rc == 601) di as smcl "{err:Network error. Please ensure that {cmd:`provider'} and {cmd:`dataset'} are valid DB.nomics endpointts}"
		exit _rc
	}
	else if (_rc > 0) {
		di as err "Kernel panic. Abort"
		exit _rc
	}
	
	/* Parse JSON */
	mata: structure = fetchjson("`jdata'", "");
	
	/* Check for error in response */
	mata: parseresperr(structure);	
	
	/* Parse metadata */
	mata: st_local("nomicsmeta", parsemeta(structure));	
	
	/* Parse dataset structure */
	mata: datainfo = fetchjson("`jdata'", "dataset");	

	/* Parse series node */
	mata: seriesinfo = fetchjson("`jdata'", "series");
	mata: numseries = fetchkeyvals(seriesinfo, ("num_found"));
	mata: st_local("series_found", numseries[1]);
	
	if (`series_found' == 0) {
		display as smcl "{err:Warning: no series found.}"
	}
	else {
		/* Data is the array containing matching series */
		mata: srsdata = seriesinfo->getNode("data");
		
		tempfile theseries
		
		nobreak {
			quietly {
			
				forvalues jj = 1/`series_found' {
					
					preserve
					
						drop _all
						
						/* Parse series data */
						capture mata: seriesformat(srsdata, `jj');
						
						if (`jj' > 1) {
							append using `theseries'
							save `theseries', replace
						}
						else {
							save `theseries'
						}
						
						if (`jj' == `series_found') {
							noi di "."
						}
						else {
							noi di "." _c
						}
					
					restore
				
				}
				
				use `theseries', clear
				
			}
		}
		
		/* Reduce space (this can be automated in the future)*/
		qui compress		

		/* Housekeeping */
		quietly {
			cleanutf8
			destring _all, replace
			remove_destrchar _all
			auto_labels _all
			foreach v of varlist _all {
				capture confirm new variable `=subinstr(itrim(trim(subinstr(strlower("`: var lab `v''"),"_"," ",.)))," ","_",.)'
				if !_rc {				
					rename `v' `=subinstr(itrim(trim(subinstr(strlower("`: var lab `v''"),"_"," ",.)))," ","_",.)'
				}
			}
		}
	}
	
	/* Add provider metadata */
	mata: metadata = ("code","name");
	mata: datafeat = fetchkeyvals(datainfo, metadata);
	mata: for (kk=1; kk<=cols(metadata); kk++) st_lchar("_dta", metadata[kk], datafeat[kk]);	
	
	display as txt "`series_found' series found and imported"
	
	/* Add metadata as dataset data characteristic */
	char _dta[provider] "`provider'"
	char _dta[dataset] "`dataset'"
	char _dta[endpoint] "`apipath'"
	char _dta[_meta] "`nomicsmeta'"	
	
end


/*6. Use single series */
program dbnomics_use

	syntax anything(name=series), PRovider(string) Dataset(string) PATH(string asis) [CLEAR DELIMiter(string)]
	
	/* Parse clear option*/
	if ("`clear'" == "") {
		if `c(width)' > 0 {
			di as err "no; data in memory would be lost. Use {cmd:clear} option"
			exit 4
		}
	} 
	else {
		clear
	}	
	
	local apipath = "`path'/`provider'/`dataset'/`series'.csv"
	
	/* Save csv locally to reduce server load in case of multiple calls */
	tempfile csvdata
	capture copy "`apipath'" `csvdata', replace	
	if (inrange(_rc,630,696) | _rc == 601) {
		if (_rc == 601) di as smcl "{err:Network error. Please ensure that {cmd:`provider'}, {cmd:`dataset'} and {cmd:`series'} are valid DB.nomics endpointts}"
		exit _rc
	}
	else if (_rc > 0) {
		di as err "Kernel panic. Abort"
		exit _rc
	}		
	
	if ("`delim'" == "") local delim tab
	
	import delimited period value using `csvdata', delim(`delim') clear
	qui gen code = "`series'"
	
	/* Housekeeping */
	quietly {
		cleanutf8
		destring _all, replace
		remove_destrchar _all
		auto_labels _all
		foreach v of varlist _all {
			capture confirm new variable `=subinstr(itrim(trim(subinstr(strlower("`: var lab `v''"),"_"," ",.)))," ","_",.)'
			if !_rc {				
				rename `v' `=subinstr(itrim(trim(subinstr(strlower("`: var lab `v''"),"_"," ",.)))," ","_",.)'
			}
		}
	}	
	
	/* Add metadata as dataset data characteristic */
	char _dta[provider] "`provider'"
	char _dta[dataset] "`dataset'"
	char _dta[series] "`series'"
	char _dta[endpoint] "`apipath'"
	
end

/* 99. Utilities */

/* Replace UNICODE characters */
program cleanutf8
	
	args noutf
	tempfile runtoclean
	
	if ("`noutf'" != "1") {	
		quietly {
			preserve
				
				tostring _all, replace force
				
				stack _all, into(strings) clear
				drop _stack
				duplicates drop
				
				moss strings, match("(\\u[0-9a-f][0-9a-f][0-9a-f][0-9a-f])") regex pref(uni)
				keep if inrange(unicount,1,.)
				
				if (`c(N)' == 0) {
					restore
					cleanutf8 1
					exit 0
				}
				
				/* pause */
				
				unab matches: unimatch?*
				
				if (`:list sizeof matches' > 1) {				
					stack `matches', into(unistr) clear
					drop _stack
				}
				else {
					keep `matches'
					rename `matches' unistr
				}
				duplicates drop
				gen unichar = ustrunescape(unistr)
				gen command = `"replace \`1' = subinstr(\`1',""' + unistr + `"",""' + unichar + `"",.)"'
				
				outfile command using `runtoclean', noquote
			
			restore
		}
	}
	
	foreach v of varlist _all {
		capture confirm string variable `v'
		if !_rc {
			if ("`noutf'" != "1") run `runtoclean' `v', nostop
			qui replace `v' = subinstr(`v',"\n","",.)
			qui replace `v' = subinstr(`v',`"\""',`"""',.)
			qui replace `v' = subinstr(`v',"\/","/",.)
		}
	}

end

/* Clean var chars */
program remove_destrchar
	
	syntax varlist
	
	foreach var of local varlist {
		local thechars : char `var'[]
		foreach ch of local thechars {
			if inlist("`ch'","destring","destring_cmd") {
				char `var'[`ch'] ""
			}
		}
	}
	
end

/* Gen var labels */
program auto_labels

	syntax varlist

	foreach var of local varlist {
		local thelab = strupper(substr("`var'",1,1)) + subinstr(substr("`var'",2,.),"_"," ",.)
		lab var `var' "`thelab'"
	}
	
end

/* Compile dimensions dict based on macval(options) */
capture program drop _optdict
program _optdict

	local cmdorig : copy local 0 
	
	if (`"`cmdorig'"' == "") {
		c_local dimdict `""'
		exit
	}
	
	tokenize `"`0'"', parse(")")
	
	local i 1
	local optlist
	local optsyn
	
	/* Parse options */	
	while (`"`macval(`i')'"' != "") {
		
		local optfull "``=2*`i'-1''"
		gettoken optcmd optval : optfull, parse("(")
		
		/* Here syntax-encode optcmd */
		mata: st_local("optcmd_enc", syntaxencode(`"`optcmd'"'))
		
		if ("`optcmd_enc'" != "") local cmdorig : subinstr local cmdorig `"`optcmd'"' `"`optcmd_enc'"'
		if ("`optcmd_enc'" != "") local optlist "`optlist' `optcmd_enc'"
		if ("`optcmd_enc'" != "") local optsyn "`optsyn' `=strlower("`optcmd_enc'")'(string asis)"
		
		if ("`=strlower("`optcmd_enc'")'" != "`optcmd_enc'") local cmdorig : subinstr local cmdorig `"`optcmd_enc'("' `"`=strlower("`optcmd_enc'")'("'
		
		/* if ("`optval'" != "") local optvals "`optvals' `=substr(`"`optval'"',2,.)'" */
		
		local `i++'
	}
	
	/* Parse options parameters */
	local 0 `", `macval(cmdorig)'"'
	syntax [anything], `optsyn'
	
	local thedict "{"
	
	foreach opt of local optlist {
		
		local theopt `""``=strlower("`opt'")''""'
		
		/* Here syntax-decode optcmd */
		mata: st_local("optcmd", syntaxdecode(`"`opt'"'))
		
		local theoptdict : subinstr local theopt `"" ""' `"",""', all
		local theoptdict2 : subinstr local theoptdict `""""' `"""', all
		
		local thedict "`thedict'"`optcmd'":[`theoptdict2'],"
	
	}
	
	/* Finalise dict */
	local thedict = substr(`"`thedict'"',1,length(`"`thedict'"')-1) + "}"
	
	/* URL encode dict */
	mata: st_local("output", urlencode(`"`thedict'"'))
	
	/* yield dict */
	c_local dimdict `"`output'"'
	
end

/* Begin mata operations */
mata

	/* Procedure to extract series data */
	void seriesformat(pointer (class libjson scalar) scalar data, real scalar cursor) {

		pointer (class libjson scalar) scalar series
		pointer (class libjson scalar) scalar value
		pointer (class libjson scalar) scalar period
		string matrix thedata
		string matrix oinfo
		string matrix oinfo_p
		string matrix odata
		string matrix output
		
		/* Loop through series */
		series = data->getArrayValue(cursor);

		/* Series data (period-value) */
		value = series->getNode("value");
		period = series->getNode("period");

		/* Parse values */
		thedata = (parsearray(period,0)',parsearray(value,0)');

		/* Other info */
		oinfo = dict2table(series, dictdim(series)[.,2] - 1);
		oinfo_p = select(oinfo, oinfo[.,1]:!="period" :& oinfo[.,1]:!="value")';

		/* Adjust other info */
		odata = J(rows(thedata), 1, oinfo_p[2,.]);

		/*Combine dataset*/
		output = thedata, odata;

		/* Export data */
		pushdata(output, (("period","value"), oinfo_p[1,.]));

	}

	string scalar parsestructure(pointer (class libjson scalar) scalar node) {
	
		pointer (class libjson scalar) scalar templ
		
		/* Two strategies:*/
		/* 1) List in dimensions_codes_order is available */
		templ = node->getNode("dimensions_codes_order");
		if (templ!=NULL) {
			return(parsearray(templ, 1));
		} else {
		/* 2) Get list of attribute names */
			string scalar output
			string rowvector columns
			templ = node->getNode("dimensions_values_labels");
			if (templ!=NULL) {
				columns = templ->listAttributeNames(0);
				output = columns[1];
				for (kk=2; kk<=cols(columns); kk++) output = output + "." + columns[kk]
				return(output);
			} else {
				output = "Not Available"
				return(output);
			}			
		}
	}

	real rowvector dictdim(pointer (class libjson scalar) scalar node) {
		
		string rowvector selector
		string matrix collector
		real scalar NR
		real scalar NC
		
		/* Parse nr. of kkeys */
		selector = node->listAttributeNames(0);
		NR = cols(selector);
		/* Flatten and get longest col */
		collector = node->flattenToKV();
		/* Initialise max */
		NC = 1
		for (kk=1; kk<=rows(collector); kk++) {
			NC = rowmax((NC, cols(tokenizer(collector[kk,1], ":"))));
		}	
		return((NR, NC + 1));	
	}

	string rowvector tokenizer(string scalar toparse, string scalar punct) {
		tok = tokens(toparse,punct);
		NC = ceil(cols(tok)/2);
		res = J(1,NC,"");
		for (kk=1; kk<=NC; kk++) {
			res[kk]=tok[kk*2-1];
		}
		return(res);
	}

	/* Parse dict of dicts. Assumption: at most x nested level */
	string matrix dict2table(pointer (class libjson scalar) scalar node, real scalar depth) {

		string matrix output
		string matrix content
		string matrix yield
		string matrix isempty
		string rowvector selector
		pointer (class libjson scalar) scalar cell
		real scalar kk
		
		/* Capture empty node */
		isempty = node->flattenToKV();
		if (rows(isempty) == 0) {
			return("0");
		}
		if (node==NULL) {
			return("0");
		}
		
		/* Parse nr. of kkeys */
		selector = node->listAttributeNames(0);
			
		/*Initialise output*/
		output = J(0, depth, "");
			
		for (kk=1; kk<=cols(selector); kk++) {
			
			cell = node->getAttribute(selector[kk]);
			
			if (cell==NULL) {
				return(0);
				exit();
			} else if (cell->isObject()) {
				if (depth <= 2) {
					content = cell->flattenToKV();
				} else {
					content = dict2table(cell, depth - 1);
				}
				if (cols(content) < cols(output)) {
					yield = (J(rows(content), 1, selector[kk]), content, J(rows(content), cols(output) - cols(content) - 1, ""));
				} else {
					yield = content;
				}
				output = output \ yield;
			} else if (cell->isString()) {
				output = output \ (selector[kk], cell->getString("",""), J(1, cols(output) - 2, ""));
			} else if (cell->isArray()) {
				output = output \ (selector[kk], cell->bracketArrayScalarValues(), J(1, cols(output) - 2, ""));
			} else {
				return(0);
				exit();
			}
		}
		return(output);
	}



	string matrix parsetree(pointer (class libjson scalar) scalar node, string rowvector dictkeys) {
		
		pointer (class libjson scalar) scalar provnode
		string matrix thetree
		
		/*Extract relevant node*/
		provnode = node->getNode("category_tree");
		
		/* Build tree table */
		thetree = getrecursive(provnode, dictkeys, 0);
		
		/*Output*/
		return(thetree);
	
	}
	
	string rowvector treekeys(string scalar keylist) {

		string rowvector tok
		real scalar NC
		string scalar dictkeys

		if (keylist != "") {
			tok = tokens(keylist,",");
			NC = ceil(cols(tok)/2);
			if (NC > 0) {
				dictkeys=J(1,NC,"");
				for (kk=1; kk<=NC; kk++) dictkeys[kk]=tok[kk*2-1];
			}
			else {
				printf("{err: Invalid key list}\n", selector);
				exit(error(198));
			}
		}
		else {
			dictkeys = ("code","name","doc_href");
		}		
		return(dictkeys);	
	}

	string matrix fetchjson(string scalar url, string scalar path) {
	
		class libjson scalar w
		pointer (class libjson scalar) scalar node
		
		/* Import JSON data*/
		jstr = w.getrawcontents(url ,J(0,0,""));
		
		/*Parse contents*/
		node = w.parse(jstr);
		
		/* Parse path option */
		if (path != "") {
			pointer (class libjson scalar) scalar pnode
			pnode = node->getNode(path);
			if (pnode != NULL) {
				return(pnode);
			}
		}		
		return(node);	
	}

	void parseresperr(pointer (class libjson scalar) scalar node) {
		
		pointer (class libjson scalar) scalar provnode
		
		/* Extract important node */
		provnode = node->getNode("error_description");
		
		/* Extract error message */
		if (provnode==NULL) {
			/*No error key found*/
			exit(0);
		} else {
			/* Display error description and exit 601 */
			if (provnode->isString()) output = provnode->getString("","");
			printf("{err: %s}\n", output);
			exit(601);
		}
	}

	string scalar parsemeta(pointer (class libjson scalar) scalar node) {

		pointer (class libjson scalar) scalar provnode
		pointer (class libjson scalar) scalar metanode
		string rowvector provnode_attr
		string scalar output

		/* Extract important node */
		provnode = node->getNode("_meta");	
		
		/* Extract error message */
		/* Initialise output str */
		output = ""
		
		if (provnode==NULL) {
			/*No meta data found*/
			return(output);
		} else {
			/* Get attributes*/
			provnode_attr = provnode->listAttributeNames(0);
			
			/* Loop through attributes and fill output */
			pointer (class libjson scalar) scalar cell
			
			for (k=1; k<=cols(provnode_attr); k++) {
				/* Get attr name */
				kk = provnode_attr[k];
				/* Get attr content */
				cell = provnode->getAttribute(kk);
				
				if (cell->isString()) {
					if (output == "")	 {
						output = kk + ": " + cell->getString("","");
					} else {
					output = output + ". " + kk + ": " + cell->getString("","");
					}
				}
			}
			return(output);		
		}
	}	
	
	void pushdata(string matrix ptable, string rowvector pheaders) {
		
		string rowvector pheadersp
		
		/* Ensure headers are proper stata var names*/
		pheadersp = J(rows(pheaders),cols(pheaders),"")
		pheadersp[.,.] = strtoname(pheaders[.,.]);
			
		/*Add info to dataset*/
		st_addobs(rows(ptable));
		st_sstore(.,st_addvar("str2045", pheadersp), ptable);	

	}
	
	string matrix json2table(pointer (class libjson scalar) scalar provnode) {
		
		/* Define json elements as libjson pointers */
		pointer (class libjson scalar) scalar arrayval
		pointer (class libjson scalar) scalar cell
		pointer (string rowvector) scalar selectors
		
		real scalar NC
		real scalar NR
		string matrix res
		
		/* Get dimensions */
		NC = strtoreal(jsoncolsArray(provnode, 1));
		if (provnode->isArray()) {
			NR = provnode->arrayLength();		
		}
		else if (provnode->isObject()) {
			string rowvector cols
			cols = provnode->listAttributeNames(0);
			NR = rows(cols');
		}		

		/* provnode is always an Array */
		selectors = getcolsArray(provnode);

		/* Initialise output */
		res = J(NR, NC, "");	
		
		/* Shamelessly adapted from insheetjson */
		/* Loop through rows and parse columns */			
		for (r=1; r<=NR; r++) {
			
			/* Get rth item from tableroot */
			arrayval = provnode->getArrayValue(r);
			
			/* Loop through columns of rth row and parse cells */
			for(c=1; c<=NC; c++) {
				
				/* The following is repeated from above */
				/* Get cell content from rownod */
				cell = arrayval->getNode(*selectors[c]);
				
				/* Cell is not empty: */
				if (cell) {
					/*Case 1: cell contains string. Getstring behaves like the dict.get() command in python */
					if (cell->isString()) res[r,c] = cell->getString("","");
					/* Case 2: cell contains array. Return list containing array values */
					else if (cell->isArray()) res[r,c] = cell->bracketArrayScalarValues();
				}
				
				/* If cell is not found leave res with blank */
					
			}
		}	
		return(res);
	}
	
	string matrix getrecursive(pointer (class libjson scalar) scalar node, string rowvector dictkeys, real scalar level) {

		/* Loop through submitted key vector and fill output */
		pointer (class libjson scalar) scalar cell
		string matrix output
		real scalar NR
		
		/*Initialise output*/
		output = J(0,cols(dictkeys)+1,"");
		
		/*Case 0: node must be Array*/
		if ( node->isObject() ) {
			/* Capture node object */
			output = output \ (strofreal(level), fetchkeyvals(node, dictkeys));
			/*Try navigating to children object */
			cell = node->getNode("children");
			/* Build exception*/
			if (cell==NULL) {
				/*Reached the end of the tree*/
				return(output);
			}
			else {
				output = output \ getrecursive(cell, dictkeys, level + 1);
				return(output);
			}
		}
		else if ( node->isArray() ) {
			/* Get array length*/
			NR = node->arrayLength();
			/*Exit if array length is zero*/
			if (NR < 1) return(output);
			for (r=1; r<=NR; r++) {
				cell = node->getArrayValue(r);
				output = output \ getrecursive(cell, dictkeys, level + 1);
			}
			return(output);
		}
		else {
			return(output);
		}
	}	

	pointer (string rowvector) getcolsArray(pointer (class libjson scalar) scalar node) {
		
		real scalar NR
		string rowvector collector
		string colvector uniquecols
		pointer (string rowvector) scalar colsel 
		
		pointer (class libjson scalar) scalar arrayval
			
		NR = node->arrayLength();
		collector = J(1,0,"");
		
		for (r=1; r<=NR; r++) {
			
			/* Get inner array val*/
			arrayval = node->getArrayValue(r);
			
			/* Update collector with node attributes */
			collector = collector, arrayval->listAttributeNames(0);
		
		}
		
		/*Use uniqrows to list all atributes*/
		uniquecols = uniqrows(collector')';
		
		colsel=J(1,cols(uniquecols),NULL)
		for (k=1; k<=cols(uniquecols); k++) colsel[k] = & (uniquecols[k]);
		
		return(colsel);
	}
	
	string rowvector parsearray(pointer (class libjson scalar) scalar node, real scalar nflag) {
		
		pointer (class libjson scalar) scalar cell
		string rowvector collector
		real scalar NR
		
		NR = node->arrayLength();
		collector = J(1,NR,"");
		
		for (r=1; r<=NR; r++) {
			
			/* Get inner array val*/
			cell = node->getArrayValue(r);
			
			if (cell->isString()) {
				
				if (nflag==. || nflag==0) {
					/* Update collector with node attributes */
					collector[r] = cell->getString("","");
				}
				else {
					if (collector[1] == "") {
						collector[1] = cell->getString("","");
					} else {
						collector[1] = collector[1] + "." + cell->getString("","");
					}
				}
			} else {
				return(0);
			}
		}
		if (nflag==. || nflag==0) {
			return(collector);		
		} else {
			return(collector[1]);
		}
	}

	/* Returns either columns of JSON node or nr. of rows. Accepts an Array of dicts */
	string matrix jsoncolsArray(pointer (class libjson scalar) scalar node, real scalar nflag) {
		
		real scalar NR
		string rowvector collector
		string colvector uniquecols
		
		pointer (class libjson scalar) scalar arrayval
			
		NR = node->arrayLength();
		collector = J(1,0,"");
		
		for (r=1; r<=NR; r++) {
			
			/* Get inner array val*/
			arrayval = node->getArrayValue(r);
			
			/* Update collector with node attributes */
			collector = collector, arrayval->listAttributeNames(0);
		
		}
		
		/*Use uniqrows to list all atributes*/
		uniquecols = uniqrows(collector');
		
		if (nflag==. || nflag==0) {
			return(uniquecols)
		}
		else {	
			return(strofreal(rows(uniquecols)));
		}
	}
	
	string matrix fetchkeyvals(pointer (class libjson scalar) scalar node, string rowvector dictkeys) {

		/* Loop through submitted key vector and fill output */
		pointer (class libjson scalar) scalar cell
		string rowvector output
		
		/* Initialise output */
		output = J(1, cols(dictkeys), "");
		
		for (k=1; k<=cols(dictkeys); k++) {
			/* Get attr content */
			cell = node->getAttribute(dictkeys[k]);		
			
			if (cell==NULL) {
				return(output);
			} else if (cell->isString()) {
				output[k] = cell->getString("","");
			} else {
				output[k] = "";
			}
		}
		return(output);
	}	

	/* URL encode, taken from libjson_source */
	string scalar urlencode(string scalar s) { 
		
		res = J(1,0,.); 
		a=ascii(s); 
		
		for(c=1;c<=cols(a); c++) { 
			if ((a[c]>=44 && a[c]<=59) || (a[c]>=64 && a[c]<=122)) {
				res=(res,a[c]);
			} else { 
				h1 = floor(a[c]/16); 
				h2 = mod(a[c],16); 
				if (h1<10) {
					h1=h1+48;
				} else {
					h1=h1+55;
				}  
				if (h2<10) {
					h2=h2+48;
				} else {
					h2=h2+55;
				} 
				res=(res, 37, h1,h2);
			} 
		} 
		
		return(char(res));
	}
	
	/* Convert to syntax-approved string */
	string scalar syntaxencode(string scalar input) {

		real rowvector ascinput
		string scalar output

		ascinput = ascii(input);
		output = "";
		for (kk=1; kk<=cols(ascinput); kk++) {
			if ((ascinput[kk] >= 1 && ascinput[kk] <=45) || (ascinput[kk] >= 58 && ascinput[kk] <=64) || (ascinput[kk] >= 91 && ascinput[kk] <=94) || (ascinput[kk] >= 123 && ascinput[kk] <=126) || (ascinput[kk] == 47 || ascinput[kk] == 96)) {
				output = output + "_" + strofreal(ascinput[kk]) + "_";
			} else {
				output = output + char(ascinput[kk]);
			}		
		}
		
		return(output);
	}
	
	/* Decode from syntax-approved string */
	string scalar syntaxdecode(string scalar input) {

		string scalar output
		
		output = input;
		for (kk=1; kk<=128; kk++) {
			output = subinstr(output, "_" + strofreal(kk) + "_", char(kk));
		}
		
		return(output);
	}	
	
	
end

exit

/* Define functions */
/*mata drop getcols()
mata drop jsoncols()
mata drop getproviders()
mata drop parseproviders()*/
/*  mata drop getcell()  */
