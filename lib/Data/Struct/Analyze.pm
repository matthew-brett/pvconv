# Data::Struct::Analyze - implements structure for Analyze 7.5 header.
# See http://www.mrc-cbu.cam.ac.uk/Imaging/analyze_fmt.html 
#
# $Id: Analyze.pm,v 1.1 2004/04/22 18:26:03 matthewbrett Exp $

package Data::Struct::Analyze;

use Data::Struct::Base;

@ISA = ('Data::Struct::Base');

use strict;

my @hdrdef  = (
		  ["sizeof_hdr",    'l', 348],
		  ["data_type",     'a10', ""],
		  ["db_name",       'a18', ''],
		  ["extents",       'l', 16384],
		  ["session_error", 's', 0],
		  ["regular",       'a', 'r'],
		  ["hkey_un0",      'c', 0],
		  
		  ["dim",           's', [4,1,1,1,1,0,0,0]],
		  ["vox_units",     'a4', 'mm'],   
		  ["cal_units",     'a8', ''],
		  ["unused1",       's', 0],
		  ["datatype",      's', 4],
		  ["bitpix",        's', 16],
		  ["dim_un0",       's', 0],
		  ["pixdim",        'f', [0,1,1,1,0,0,0,0]],
		  ["vox_offset",    'f', 0],
		  [['funused1', "scale_factor"],  'f', 1],
		  ["funused2",      'f', 0], 
		  ["funused3",      'f', 0],
		  ["cal_max",       'f', 0],   
		  ["cal_min",       'f', 0],
		  ["compressed",    'f', 0],
		  ["verified",      'f', 0],
		  ["glmax",         'l', 0],
		  ["glmin",         'l', 0],
		  
		  ["descrip",       'a80', ''],
		  ["aux_file",      'a24', ''],
		  ["orient",        'c', 0],   
		  ["originator",    's', [0,0,0,0,0]],
		  ["generated",     'a10', ''], 
		  ["scannum",       'a10', ''],
		  ["patient_id",    'a10', ''],  
		  ["exp_date",      'a10', ''],
		  ["exp_time",      'a10', ''],     
		  ["hist_un0",      'a3', ''],
		  ["views",         'l', 0],     
		  ["vols_added",    'l', 0],
		  ["start_field",   'l', 0],    
		  ["field_skip",    'l', 0],
		  ["omax",          'l', 0],   
		  ["omin",          'l', 0],
		  ["smax",          'l', 0],    
		  ["smin",          'l', 0],
		  );

my $swaptest = sub {
    my $self = shift;
    return ($self->sizeof_hdr()==1543569408 ||
	    ($self->dim(0) < 0 || $self->dim(0) > 15));
};

sub new {
    my $that = shift;
    my $class = ref($that) || $that;
    my $self = $class->SUPER::new(\@hdrdef, 
			  'verbose'=> 0, 
			  'extension' => 'hdr',
			  'enforce_extension' => 1, 
			  'endian', {'default_in', 'native',
				     'try_unswap', 1,
				     'swaptest',$swaptest,},
			  @_);
    bless $self, $class; 
    return $self;
}
1;
