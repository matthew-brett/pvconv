# This -*- perl -*- script writes the Makefile for pvconv
# $Id: Makefile.PL,v 1.1 2004/04/22 18:26:03 matthewbrett Exp $

require 5.005;
use strict;
use ExtUtils::MakeMaker qw(WriteMakefile prompt);

WriteMakefile(
	      NAME          => 'pvconv',
	      VERSION_FROM  => 'bin/pvconv.pl',
	      EXE_FILES     => [<bin/*.pl>],
	      BUILD_REQUIRES => { 'Math::Matrix'     => "0.4",
				 'Getopt::ArgvFile' => "1.06",
			     },
	      PREREQ_PM     => { 'Math::Matrix'     => "0.4",
				 'Getopt::ArgvFile' => "1.06",
			     },
	      'dist'        => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	      );



package MY;

# Determine things that should *not* be installed
sub libscan
{
    my($self, $path) = @_;
    return '' if $path =~ m:\bCVS/:;
    return '' if $path =~ m/~$/;
    $path;
}

# Pass pvconv version number to pod2man
sub manifypods
{
    my $self = shift;
    my $ver = $self->{VERSION} || "";
    local($_) = $self->SUPER::manifypods(@_);
    s/pod2man\s*$/pod2man --release pvconv-$ver/m;
    $_;
}

