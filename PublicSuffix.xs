/* 
 * PublicSuffix.xs 
 *
 * Copyright (C) 2014 Blekko, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <float.h>

#define BASEDOMAIN_STASH basedomain_stash

static HV *basedomain_stash;

typedef struct bdnode {
    // entry 0 is the leaf node marker
    // entries 1-255 are links of the TRIE structer
    struct bdnode *next[256];
} BDNODE;

typedef struct {
    BDNODE *tree;
} BASEDOMAIN;


BDNODE tree;
int tree_initialized = 0;
int debug = 0;

int valid_domain (BDNODE *ptr);
int valid_bang_domain (BDNODE *ptr);
void dump_tree();
void print_tree(BDNODE *ptr, char *str, int pos);
void gen_strings (BDNODE *ptr, AV *levels, int level);
BDNODE* add_string  (BDNODE *ptr, char *str);
char* _base_domain (SV *domain, int strict_mode);
char* base_domain (SV *domain);
char* public_suffix (SV *domain);
BDNODE * match_word(BDNODE *ptr, char *str, int *j);
BDNODE * match_wildcard(BDNODE *ptr, char *str, int *j);

// valid_domain()  - check that given trie pointer is a leaf node of a valid base domain
int
valid_domain (BDNODE *ptr) 
{
    // valid leaf node is (ptr->next['.']->next[0] != NULL)
    if (ptr && 
        ptr->next['.'] != NULL &&
        ptr->next['.']->next != NULL &&
        ptr->next['.']->next[0] != NULL ) 
    {
        return 1;
    }
    return 0;
}

// valid_bang_domain()  - check that given trie pointer is a ! rule leaf node
int
valid_bang_domain (BDNODE *ptr) 
{
    // valid leaf node is (ptr->next['.']->next[0] != NULL)
    if (ptr && 
        ptr->next['.'] != NULL &&
        ptr->next['.']->next != NULL &&
        ptr->next['.']->next['!'] != NULL ) 
    {
        return 1;
    }
    return 0;
}

// add_string()    - helper function to allocate/set new TRIE nodes for a given string/word
// Input:
//    ptr  - BDNODE pointer for the where the string TRIE data should be added
//    str  - char * of the string being added to the TRIE
// Output:
//    returns a pointer into the TRIE where the last word of the domain is located,
//    plus a trailing '.' This is where the next part of the domain will be added.
//
BDNODE *
add_string (BDNODE *ptr, char *str) 
{
    unsigned char c;
    int i = strlen(str) - 1;

    for (; i >= 0 ; i--) {
        c = str[i];
        if (ptr->next[c] == NULL) {
            ptr->next[c] = (BDNODE *)safemalloc(sizeof(BDNODE));
            Zero(ptr->next[c],1,BDNODE);
        }
        ptr = ptr->next[c];
    }
    c = '.';
    if (ptr->next[c] == NULL) {
      ptr->next[c] = (BDNODE *)safemalloc(sizeof(BDNODE));
      Zero(ptr->next[c],1,BDNODE);
    }
    ptr = ptr->next[c];

    return ptr;
}


// gen_strings()    - generate part of the domain name TRIE
//
// INPUT:
//    root     - pointer of the TRIE to build
//    levels   - PERL array of array refs, each sub-array ref is the list
//               of sub-domain parts (words).
//    level    - the current level we're building, used as the index of
//               the @levels array.

void
gen_strings (BDNODE *root, AV *levels, int level) 
{

    SV **cur_level;
    SV **word;
    AV *wordav;
    int wordav_len;
    int i;
    BDNODE *ptr;

    if (av_len(levels) < level) {
        // no more levels, insert sentinel to say this is a valid end of a base domain
        if (root->next[0] == NULL) {
            root->next[0] = (BDNODE *)safemalloc(sizeof(BDNODE));
            Zero(root->next[0],1,BDNODE);
        }
        return;
    }
    else {
        // For each domain part (word) we recersively generate the Trie structure
        // of the all the deeper levels.
        cur_level = av_fetch (levels, level, 0);
        wordav = (AV *) SvRV (*cur_level);
        wordav_len = av_len(wordav);

        for (i = 0; i <= wordav_len; ++i) {
            word = av_fetch (wordav, i, 0);
            if (debug > 2) { printf("gen_strings: level=%d  word=%s\n",level, SvPVX(*word)); }
            ptr = add_string(root, SvPVX(*word));
            gen_strings(ptr, levels, level +1);
        }
    }
}

// match_word - determined if a given string exists in a portion of the TRIE
// Input:
//     ptr  - pointer to a sup-part of the TRIE
//     str  - pointer to the string we're trying to match
//     j    - offset into the string str we're trying to match
// Output:
//     pointer to the last point in the TRIE of the match, not including the trailing '.'
//     returns NULL if string does not match
BDNODE *
match_word(BDNODE *ptr, char *str, int *j)
{
    int i = *j;
    int k;

    if (str[i] == '.') {
        // Except for the right most, top level domain match, we will start with 
        // str[i] pointing to the "." character between sub domain parts. Skip this.
        ptr = ptr->next[(unsigned char)str[i--]];
        if ((ptr == NULL) || (i < 0)) {
            return NULL;
        }
    }
    
    // characters ! and * have special meaning in the TRIE, and are not valid domain chars
    if (str[i] == '!' || str[i] == '*') {
        if (debug) {
            printf("FAILED match_word: [");
            for (k = i; k <= *j; k++) { printf ("%c",str[k]); }
            printf("]\n");
        }
	return NULL;
    }

    // try to match next subdomain part in the trie
    while ((i >= 0) && (ptr->next[(unsigned char)str[i]]) && (str[i] != '.'))  {
        ptr = ptr->next[(unsigned char)str[i--]];
    }
    if (i < 0) { i = 0; }

    if ((i < *j) && ptr && ptr->next && (i == 0 || (str[i] == '.')) && ptr->next['.']) {
        *j = i;
        return ptr;
    }
    else {
        if (debug) {
            printf("FAILED match_word: [");
            for (k = i; k <= *j; k++) { printf ("%c",str[k]); }
            printf("]\n");
        }
    }
    
    return NULL;
    
}

// match_wildcard - determine if a given string exists in a portion of the TRIE
// Input:
//     ptr  - pointer to a sup-part of the TRIE
//     str  - pointer to the string we're trying to match
//     j    - offset into the string str we're trying to match
// Output:
//     pointer to the last point in the TRIE of the match, not including the trailing '.'
//     returns NULL if string is empty or this is not a wildcard node in the TRIE

BDNODE *
match_wildcard(BDNODE *ptr, char *str, int *j)
{
    int i = *j;
    int k;

    if (str[i] == '.') {
        // Except for the right most, top level domain match, we will start with 
        // str[i] pointing to the "." character between sub domain parts. Skip this.
        ptr = ptr->next[(unsigned char)str[i--]];
        if ((ptr == NULL) || (i < 0)) {
            return NULL;
        }
    }
    
    // characters ! and * have special meaning in the TRIE, and are not valid domain chars
    if (str[i] == '!' || str[i] == '*') {
        if (debug) {
            printf("FAILED match_wildcard: [");
            for (k = i; k <= *j; k++) { printf ("%c",str[k]); }
            printf("]\n");
        }
	return NULL;
    }

    // look for the '*' and match that in the trie to the next part of the domain
    if ((i > 0) && (ptr->next['*'])) {
        ptr = ptr->next['*'];
        for( ; (i > 0) && (str[i] != '.'); i--);
    }
    
    if ((i < *j) && ptr && ptr->next && (i == 0 || (str[i] == '.')) && ptr->next['.']) {
        *j = i;
        return ptr;
    }
    else {
        if (debug) {
            printf("FAILED match_wildcard: [");
            for (k = i; k <= *j; k++) { printf ("%c",str[k]); }
            printf("]\n");
        }
    }

    return NULL;

}

// print_tree - print out all possible entries in the TRIE
void
print_tree(BDNODE *ptr, char *str, int pos)
{
    int c;

    str[pos] = '\0';
    
    if (ptr == NULL) {
        printf("%s\n",str);
        return;
    }
    
    for(c = 0; c < 256; c++) {
        if (ptr->next[c] != NULL) {
            if (c == 0) { 
                str[pos] = '\0'; 
                printf("%s\n",str);
            }
            else {
                str[pos] = c;
                print_tree(ptr->next[c],str,pos+1);
            }
        }
    }
}

// initialize_tree 
//    If Trie is not initialized then we need to call out to the PERL functions 
//    because all the configuration data lives in the .pm file.
void 
initialize_tree()
{
    CV *dd_cv = NULL;
    int count;

    if ((!tree_initialized) && 
        (dd_cv = perl_get_cv( "Net::Domain::PublicSuffix::gen_basedomain_tree", 0 )) != NULL ) {

        dSP ;

        ENTER ;
        SAVETMPS ;

        PUSHMARK( sp );
        PUTBACK ;

        count = perl_call_pv( "Net::Domain::PublicSuffix::gen_basedomain_tree", G_SCALAR );

        SPAGAIN ;

        PUTBACK ;
        FREETMPS ;
        LEAVE ;

        tree_initialized = 1;
    }
}

//  private function that performs the work for base_domain() and public_suffix()
char *
_base_domain (SV *domain, int strict)
{
    char *str;
    int valid = 0;
    int seen_wildcard  = 0;
    int seen_midpattern_wildcard  = 0;   // only occur in .us domains
    int i;
    BDNODE *ptr   = &tree;
    BDNODE *ptr2  = NULL;
    BDNODE *wildcard_backtrack_ptr  = NULL;

    if (debug && strict) {
        printf("Using strict domain matching.\n");
    }
    
    if (!tree_initialized) {
        initialize_tree();
    }
    ptr = &tree;
    
    if (!tree_initialized || ptr == NULL ) {
        printf("Basedomain FAIL: can't initialize state machine.\n");
    }
    
    if (SvOK(domain) && (tree_initialized) && (ptr != NULL)) {
        str = SvPV_nolen(domain);
        i = strlen(str) - 1;
        
        if (i < 0 || str[i] == '.') {
            // edge cases: empty string
            //             trailing .  (foobar.com.)
            return "";
        }
        else if (isdigit(str[i])) {
            //  edge case: tlds don't contain numbers
            //  number (most likely an IP number "10.1.2.3")
            if (strict || i > 15) {
                // strictly speaking an ip address is not a domain name
                return "";
            }
            else {
                // only a rudamentary test, that's not why we're here
                while (i-- && ( isdigit(str[i]) || str[i] == '.')) { };
                if (i == -1) {
                    i = 0;
                    return str;
                }
                else {
                    return "";
                }
            }
        }
        else {
            // primary use case 
            ptr2 = ptr;
            while (ptr2 && (i > 0)) {
                ptr2 = match_word(ptr, str, &i);
                if (ptr2 == NULL) {
		    // word match failed, see if there is a wildcard in the TRIE and try matching that 
		    ptr2 = match_wildcard(ptr, str, &i);
                    if (ptr2) {
                        seen_wildcard++;
			wildcard_backtrack_ptr = ptr;
			if (debug) { 
			  printf ("matched wildcard: %s\n", str + i);
			  printf ("setting wildcard_backtrack_ptr\n"); 
			}
                    }
                }
                else {
		    // word matched 
                    if (debug) { printf ("matched word:     %s\n", str + i); }
		    if (seen_wildcard) {
		        seen_midpattern_wildcard++;
			if (debug) { printf ("matched word after wildcard. setting seen_midpattern_wildcard\n"); }
		    }
		    if (wildcard_backtrack_ptr) {
		        // if we see a word match, no backtracking 
		        if (debug) { printf ("removing wildcard_backtrack_ptr\n"); }
			wildcard_backtrack_ptr = NULL;
		    }
                }
                if (ptr2) {
                    ptr = ptr2;
                }
            }
            
	    if (valid_bang_domain(ptr)) {
	        // this is a valid domain if we've stopped at a leaf node
                valid = 1;
		// set seen_*wildcard variables because ! rules don't have wildcards
		seen_midpattern_wildcard = 1;
		seen_wildcard = 1;
                if (debug) { printf("ptr points to a VALID ! DOMAIN: %s\n",str+i);}
	    }
	    else if (valid_domain(ptr)) {
	        // this is a valid domain if we've stopped at a leaf node
	        valid = 1;
                if (debug) { printf("ptr points to a VALID DOMAIN: %s\n",str+i); }
            }

	    if (! valid && ( wildcard_backtrack_ptr != NULL ) && seen_wildcard && ! seen_midpattern_wildcard) {
	      // the current match is not valid, 
	      // we've seen a wildcard without matching a following word in the TRIE
              // so we want to see if the last successful match was valid domain leaf node in the TRIE
	      // and then skip consuming one more domain level, as we've already seen the wildcard level
	      //
	      // for example:  www.m.wi.us  -> m.wi.us triggers a partial match
	      if (valid_domain(wildcard_backtrack_ptr)) {
                valid = 1;
                if (debug) { printf("wildcard_backtrack_ptr points to a VALID DOMAIN: %s\n",str+i); }
	      }
	      seen_midpattern_wildcard = 1;  // to skip matching one more level
	    }

            if ((! strict ) && (ptr == &tree) && (i > 0)) {
                // special case for non-sctrict mode, TLD is not valid so we try to
                // capture what looks like the TLD
                for(--i ; (i >= 0) && (str[i] != '.'); i--) { };
                if (i < 0) { i = 0; }
                if (debug) { printf ("consuming non-valid TLD: %s\n", str + i); }
	    }
            
            // At this point we've matched a domain, if there was a valid domain suffix
            if ((! seen_midpattern_wildcard ) && (i > 0)) {
	      if (strict && (i > 0) && (str[i-1] == '!' || str[i-1] == '*')) {
		    valid = 0;
		    if (debug) { printf ("domain contains invalid chars, NOT valid: %s\n", str + i -1); }
	        }
		else {
		    // now we consume one more level, unless we saw a mid-pattern
		    // wildcard, such as in some .us domains
		    for(--i ; (i >= 0) && (str[i] != '.'); i--) { seen_wildcard++; };
		    if (i < 0) { i = 0; }
		    if (debug) { printf ("skip over final wildcard: %s\n", str + i); }
		}
            }
	    else if (!seen_midpattern_wildcard) {
	        // we have a valid domain, but missing the the extra domain level
                valid = 0;
                if (debug) { printf ("missing final wildcard, NOT valid: %s\n", str + i); }
	    }

            if (! seen_wildcard ) {
                valid = 0;
            }
            
            // matching stops on the '.' (or if i==0) We need chop the leading '.' off
            if (str[i] == '.') {
                i++;
            }

            if (debug && valid) {
                printf("VALID DOMAIN: %s\n",str+i);
            }
            
            if (strict && ! valid) {
		return "";
            }
            else {
                // non strict mode will return partial matches like "com" or "tn.us" 
	        return(str + i);
            }
        }
    }
    else {
        return "";
    }

    return "";
}

/////////////////////////////////////////////////////////////////////////////
// XS interface functions

MODULE = Net::Domain::PublicSuffix              PACKAGE = Net::Domain::PublicSuffix

BOOT:
{
    // put code that runs once at load time here
    basedomain_stash         = gv_stashpv ("Net::Domain::PublicSuffix", 1);
}

PROTOTYPES: ENABLE

char *
base_domain (domain, ... )
    SV *domain;

    CODE:
{
    int strict = 0;
    if (items > 2) {
        printf("Net::Domain::PublicSuffix::base_domain() called with too many arguments\n");
    }
    else if (items == 2) {
        strict = (int)SvNV(ST(1));
    }
    
    RETVAL = _base_domain(domain,strict);
}
    OUTPUT:     
        RETVAL  


char *
public_suffix (domain)
    SV *domain;

    CODE:
{
  RETVAL = _base_domain(domain, 1);
}
    OUTPUT:     
        RETVAL  

void
gen_tree (levels)
    AV     *levels;

    CODE:
{
    gen_strings(&tree,levels,0);
}


void
set_debug_level (debug_level)
    int debug_level;
    
    CODE:
{
    debug = debug_level;
}

void
dump_tree ()
    CODE:
{
    char *str;

    if (!tree_initialized) {
        initialize_tree();
    }
    
    printf("Dumping all possilble base domain patterns: (patterns read right-to-left)\n");
    str = (char *) safemalloc(4096);
    print_tree(&tree,str,0);
    safefree(str);
}
