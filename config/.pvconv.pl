# Configuration file for pvconv.pl

# data search path, in search order
-dbpath /cbu/imagers/wbic_data

# file name ending for protocol regexps
# format [suffix]=[regexp]
-ptype SPGR=spgr
-ptype anatomique=anatom
-ptype T3=tripilot
-ptype template=template
-ptype PD-T2=pd-t2
-ptype EPI=(epi|new90|new64)
-ptype phasemap=phase

# frecofix by default
-frecofix

# omit subject information from brkhdr file
-anon
