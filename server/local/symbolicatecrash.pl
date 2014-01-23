#!/usr/bin/perl -w
#
# This script parses a crashdump file and attempts to resolve addresses into function names.
#
# It finds symbol-rich binaries by:
#   a) searching in Spotlight to find .dSYM files by UUID, then finding the executable from there.
#       That finds the symbols for binaries that a developer has built with "DWARF with dSYM File".
#   b) searching in various SDK directories.
#
# Copyright (c) 2008-2011 Apple Inc. All Rights Reserved.
#
#

use strict;
use warnings;
use Getopt::Std;
use Cwd qw(realpath);
use Math::BigInt;
use List::MoreUtils qw(uniq);
use File::Basename qw(basename);
use File::Glob ':glob';
use Env qw(DEVELOPER_DIR);
use Config;
no warnings "portable";

require bigint;
if($Config{ivsize} < 8) {
    bigint->import(qw(hex));
}

#############################

# Forward definitons
sub usage();

#############################

# read and parse command line
my %opt;
$Getopt::Std::STANDARD_HELP_VERSION = 1;

getopts('hvo:',\%opt);

usage() if $opt{'h'};

#############################

# have this thing to de-HTMLize Leopard-era plists
my %entity2char = (
    # Some normal chars that have special meaning in SGML context
    amp    => '&',  # ampersand 
    'gt'    => '>',  # greater than
    'lt'    => '<',  # less than
    quot   => '"',  # double quote
    apos   => "'",  # single quote
    );

#############################

# Find otool from the latest iphoneos
my $otool = `'/usr/bin/xcrun' -sdk iphoneos -find otool`;
my $atos  = `'/usr/bin/xcrun' -sdk iphoneos -find atos`;
my $lipo  = `'/usr/bin/xcrun' -sdk iphoneos -find lipo`;
my $size  = `'/usr/bin/xcrun' -sdk iphoneos -find size`;

chomp $otool;
chomp $atos;
chomp $lipo;
chomp $size;

print STDERR "otool path is '$otool'\n" if $opt{v};
print STDERR "atos path is '$atos'\n" if $opt{v};
print STDERR "lipo path is '$lipo'\n" if $opt{v};
print STDERR "size path is '$size'\n" if $opt{v};

#############################
# run the script

symbolicate_log(@ARGV);

exit 0;

#############################

# begin subroutines

sub HELP_MESSAGE() {
    usage();
}

sub usage() {
print STDERR <<EOF;
usage: 
    $0 [-h] [-o <OUTPUT_FILE>] LOGFILE [SYMBOL_PATH ...]
    
    Symbolicates a crashdump LOGFILE which may be "-" to refer to stdin. By default,
    all heuristics will be employed in an attempt to symbolicate all addresses. 
    Additional symbol files can be found under specified directories.
    
Options:
    
    -o  If specified, the symbolicated log will be written to OUTPUT_FILE (defaults to stdout)
    -h  Display this message
    -v  Verbose
EOF
exit 1;
}

##############

sub getSymbolDirPaths {
    my ($osVersion, $osBuild) = @_;
    
    print STDERR "(\$osVersion, \$osBuild) = ($osVersion, $osBuild)\n" if $opt{v};
    
    my $versionPattern = "{$osVersion ($osBuild),$osVersion,$osBuild}";
    #my $versionPattern  = '*';
    print STDERR "\$versionPattern = $versionPattern\n" if $opt{v};
    
    my @result = grep { -e && -d } bsd_glob('{/System,,~}/Library/Developer/Xcode/iOS DeviceSupport/'.$versionPattern.'/Symbols*', GLOB_BRACE | GLOB_TILDE);
    
    foreach my $foundPath (`mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode' || kMDItemCFBundleIdentifier == 'com.apple.Xcode'"`) {
        chomp $foundPath;
        my @pathResults = grep { -e && -d && !/Simulator/ }  bsd_glob($foundPath.'/Contents/Developer/Platforms/*.platform/DeviceSupport/'.$versionPattern.'/Symbols*/');
        push(@result, @pathResults);
    }
    
    print STDERR "Symbol directory paths:  @result\n" if $opt{v};
    return @result;
}

sub getSymbolPathFor_searchpaths {
    my ($bin,$path,$build,@extra_search_paths) = @_;
    my @result;
    for my $item (@extra_search_paths)
    {
        my $glob = "$item"."{$bin,*/$bin,$path}*";
        #print STDERR "\nSearching pattern: [$glob]..." if $opt{v};
        push(@result, grep { -e && (! -d) } bsd_glob ($glob, GLOB_BRACE));
    }
    
    print STDERR "\nSearching [@result]..." if $opt{v};
    return @result;
}

sub getSymbolPathFor_uuid{
    my ($uuid, $uuidsPath) = @_;
    $uuid or return undef;
    $uuid =~ /(.{4})(.{4})(.{4})(.{4})(.{4})(.{4})(.{8})/;
    return Cwd::realpath("$uuidsPath/$1/$2/$3/$4/$5/$6/$7");
}

# Look up a dsym file by UUID in Spotlight, then find the executable from the dsym.
sub getSymbolPathFor_dsymUuid{
    my ($uuid,$arch) = @_;
    $uuid or return undef;
    
    # Convert a uuid from the crash log, like "c42a118d722d2625f2357463535854fd",
    # to canonical format like "C42A118D-722D-2625-F235-7463535854FD".
    my $myuuid = uc($uuid);    # uuid's in Spotlight database are all uppercase
    $myuuid =~ /(.{8})(.{4})(.{4})(.{4})(.{12})/;
    $myuuid = "$1-$2-$3-$4-$5";
    
    # Do the search in Spotlight.
    my $cmd = "mdfind \"com_apple_xcode_dsym_uuids == $myuuid\"";
    print STDERR "Running $cmd\n" if $opt{v};
    
    my @dsym_paths    = ();
    my @archive_paths = ();
    
    foreach my $dsymdir (split(/\n/, `$cmd`)) {
        $cmd = "mdls -name com_apple_xcode_dsym_paths ".quotemeta($dsymdir);
        print STDERR "Running $cmd\n" if $opt{v};
        
        my $com_apple_xcode_dsym_paths = `$cmd`;
        $com_apple_xcode_dsym_paths =~ s/^com_apple_xcode_dsym_paths\ \= \(\n//;
        $com_apple_xcode_dsym_paths =~ s/\n\)//;
        
        my @subpaths = split(/,\n/, $com_apple_xcode_dsym_paths);
        map(s/^[[:space:]]*\"//, @subpaths);
        map(s/\"[[:space:]]*$//, @subpaths);
        
        push(@dsym_paths, map($dsymdir."/".$_, @subpaths));
        
        if($dsymdir =~ m/\.xcarchive$/) {
            push(@archive_paths, $dsymdir);
        }
    }
    
    @dsym_paths = uniq(@dsym_paths);
    
    my @exec_names  = map(basename($_), @dsym_paths);
    @exec_names = uniq(@exec_names);
    
    print STDERR "\@dsym_paths = ( @dsym_paths )\n" if $opt{v};
    print STDERR "\@exec_names = ( @exec_names )\n" if $opt{v};
    
    my @app_bundles_next_to_dsyms;
    foreach my $dsymdir (@dsym_paths) {
        my ($dsympath) = $dsymdir =~ /(^.*)\.dSYM/i;
        push(@app_bundles_next_to_dsyms, $dsympath . '.app');
    }
    
    my @exec_paths  = ();
    foreach my $exec_name (@exec_names) {
        #We need to find all of the apps with the given name (both in- and outside of any archive)
        #First, use spotlight to find un-archived apps:
        my $cmd = "mdfind \"kMDItemContentType == com.apple.application-bundle && (kMDItemAlternateNames == '$exec_name.app' || kMDItemDisplayName == '$exec_name' || kMDItemDisplayName == '$exec_name.app')\"";
        print STDERR "Running $cmd\n" if $opt{v};
        
        my @app_bundles = (@app_bundles_next_to_dsyms, split(/\n/, `$cmd`));
        foreach my $app_bundle (@app_bundles) {
            if( -f "$app_bundle/$exec_name") {
                push(@exec_paths, "$app_bundle/$exec_name");
            }
        }
        
        #Find any naked executables
        $cmd = "mdfind \"kMDItemContentType == public.unix-executable && kMDItemDisplayName == '$exec_name'\"";
        print STDERR "Running $cmd\n" if $opt{v};
        
        foreach my $exec_file (split(/\n/, `$cmd`)) {
            if( -f "$exec_file") {
                push(@exec_paths, "$exec_file");
            }
        }
        
        #Next, try to find paths within any archives
        foreach my $archive_path (@archive_paths) {
            my $cmd = "find \"$archive_path/Products\" -name \"$exec_name.app\"";
            print STDERR "Running $cmd\n" if $opt{v};
            
            foreach my $app_bundle (split(/\n/, `$cmd`)) {
                if( -f "$app_bundle/$exec_name") {
                    push(@exec_paths, "$app_bundle/$exec_name");
                }
            }
        }
    }
    
    if ( @exec_paths >= 1 ) {
        foreach my $exec (@exec_paths) {
            if ( !matchesUUID($exec, $uuid, $arch) ) {
                print STDERR "UUID of executable is: $uuid\n" if $opt{v};
                print STDERR "Executable name: $exec\n\n" if $opt{v};
                print STDERR "UUID doesn't match dsym for executable $exec\n" if $opt{v};
            } else {
                print STDERR "Found executable $exec\n" if $opt{v};
                return $exec;
            }
        }
    }
    
    print STDERR "Did not find executable for dsym\n" if $opt{v};
    return undef;
}

#########

sub matchesUUID {  
    my ($path, $uuid, $arch) = @_;
    
    if ( ! -f $path ) {
        print STDERR "## $path doesn't exist " if $opt{v};
        return 0;
    }
    
    my $cmd = "$lipo -info '$path'";
    print STDERR "Running $cmd\n" if $opt{v};
    
    my $lipo_result = `$cmd`;
    if( index($lipo_result, $arch) < 0) {
        print STDERR "## $path doesn't contain $arch slice\n" if $opt{v};
        return 0;
    }
    
    $cmd = "$otool -arch $arch -l '$path'";
    
    print STDERR "Running $cmd\n" if $opt{v};
    
    my $TEST_uuid = `$cmd`;
    
    if ( $TEST_uuid =~ /uuid ((0x[0-9A-Fa-f]{2}\s+?){16})/ || $TEST_uuid =~ /uuid ([^\s]+)\s/ ) {
        my $test = $1;
        
        if ( $test =~ /^0x/ ) {
            # old style 0xnn 0xnn 0xnn ... on two lines
            $test =  join("", split /\s*0x/, $test);
            
            $test =~ s/0x//g;     ## remove 0x
            $test =~ s/\s//g;     ## remove spaces
        } else {
            # new style XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
            $test =~ s/-//g;     ## remove -
            $test = lc($test);
        }
        
        if ( $test eq $uuid ) {
            ## See that it isn't stripped.  Even fully stripped apps have one symbol, so ensure that there is more than one.
            my ($nlocalsym) = $TEST_uuid =~ /nlocalsym\s+([0-9A-Fa-f]+)/;
            my ($nextdefsym) = $TEST_uuid =~ /nextdefsym\s+([0-9A-Fa-f]+)/;
            my $totalsym = $nextdefsym + $nlocalsym;
            print STDERR "\nNumber of symbols in $path: $nextdefsym + $nlocalsym = $totalsym\n" if $opt{v};
            return 1 if ( $totalsym > 1 );
                
            print STDERR "## $path appears to be stripped, skipping.\n" if $opt{v};
        } else {
            print STDERR "Given UUID $uuid for '$path' is really UUID $test\n" if $opt{v};
        }
    } else {
        print STDERR "Can't understand the output from otool ($TEST_uuid -> $cmd)\n";
        return 0;
    }

    return 0;
}


sub getSymbolPathFor {
    my ($path,$build,$uuid,$arch,@extra_search_paths) = @_;
    
    # derive a few more parameters...
    my $bin = ($path =~ /^.*?([^\/]+)$/)[0]; # basename
    
    # This setting can be tailored for a specific environment.  If it's not present, oh well...
    my $uuidsPath = "/Volumes/Build/UUIDToSymbolMap";
    if ( ! -d $uuidsPath ) {
        #print STDERR "No '$uuidsPath' path visible." if $opt{v};
    }
    
    # First try the simplest route, looking for a UUID match.
    my $out_path;
    $out_path = getSymbolPathFor_uuid($uuid, $uuidsPath);
    undef $out_path if ( defined($out_path) && !length($out_path) );
    
    print STDERR "--[$out_path] "  if defined($out_path) and $opt{v};
    print STDERR "--[undef] " if !defined($out_path) and $opt{v};
    
    if ( !defined($out_path) || !matchesUUID($out_path, $uuid, $arch)) {
        undef $out_path;
        
        for my $func (
            \&getSymbolPathFor_searchpaths,
            ) {
                my @out_path_arr = &$func($bin,$path,$build,@extra_search_paths);
                if(@out_path_arr) {
                    foreach my $temp_path (@out_path_arr) {
                        
                        print STDERR "--[$temp_path] "  if defined($temp_path) and $opt{v};
                        print STDERR "--[undef] " if !defined($temp_path) and $opt{v};
                        
                        if ( defined($temp_path) && matchesUUID($temp_path, $uuid, $arch) ) {
                            $out_path = $temp_path;
                            @out_path_arr = {};
                        } else {
                            undef $temp_path;
                            print STDERR "-- NO MATCH\n"  if $opt{v};
                        }
                    }
                } else {
                    print STDERR "-- NO MATCH\n"  if $opt{v};
                }              
                
                last if defined $out_path;
            }
    }
    # if $out_path is defined here, then we have already verified that the UUID matches
    if ( !defined($out_path) ) {
        print STDERR "Searching in Spotlight for dsym with UUID of $uuid\n" if $opt{v};
        $out_path = getSymbolPathFor_dsymUuid($uuid, $arch);
        undef $out_path if ( defined($out_path) && !length($out_path) );
    }
    
    if (defined($out_path)) {
        print STDERR "-- MATCH\n"  if $opt{v};
        return $out_path;
    }
    
    print STDERR "## Warning: Can't find any unstripped binary that matches version of $path\n" if $opt{v};
    print STDERR "\n" if $opt{v};
    
    return undef;
}

###########################
# crashlog parsing
###########################

# options:
#  - regex: don't escape regex metas in name
#  - continuous: don't reset pos when done.
#  - multiline: expect content to be on many lines following name
sub parse_section {
    my ($log_ref, $name, %arg ) = @_;
    my $content;
    
    $name = quotemeta($name) 
    unless $arg{regex};
    
    # content is thing from name to end of line...
    if( $$log_ref =~ m{ ^($name)\: [[:blank:]]* (.*?) $ }mgx ) {
        $content = $2;
        $name = $1;
        
        # or thing after that line.
        if($arg{multiline}) {
            $content = $1 if( $$log_ref =~ m{ 
                \G\n    # from end of last thing...
                (.*?) 
                (?:\n\s*\n|$) # until next blank line or the end
            }sgx ); 
        }
    } 
    
    pos($$log_ref) = 0 
    unless $arg{continuous}; 
    
    return ($name,$content) if wantarray;
    return $content;
}

# convenience method over above
sub parse_sections {
    my ($log_ref,$re,%arg) = @_;
    
    my ($name,$content);
    my %sections = ();
    
    while(1) {
        ($name,$content) = parse_section($log_ref,$re, regex=>1,continuous=>1,%arg);
        last unless defined $content;
        $sections{$name} = $content;
    } 
    
    pos($$log_ref) = 0;
    return \%sections;
}

sub parse_images {
    my ($log_ref, $report_version) = @_;
    
    my $section = parse_section($log_ref,'Binary Images Description',multiline=>1);
    if (!defined($section)) {
        $section = parse_section($log_ref,'Binary Images',multiline=>1); # new format
    }
    if (!defined($section)) {
        die "Error: Can't find \"Binary Images\" section in log file";
    }
    
    my @lines = split /\n/, $section;
    scalar @lines or die "Can't find binary images list: $$log_ref";
    
    my %images = ();
    my ($pat, $app, %captures);

    # FIXME: This should probably be passed in as an argument
    my $default_arch = 'armv6';
    
    #To get all the architectures for string matching.
    my $architectures = "armv[4-8][tfsk]?|arm64";
    
    # Once Perl 5.10 becomes the default in Mac OS X, named regexp 
    # capture buffers of the style (?<name>pattern) would make this 
    # code much more sane.
    if($report_version == 102 || $report_version == 103) { # Leopard GM                                                                                                                                            
        $pat = '                                                                                                                                                                                                      
            ^\s* (\w+) \s* \- \s* (\w+) \s*     (?# the range base and extent [1,2] )                                                                                                                                 
            (\+)?                               (?# the application may have a + in front of the name [3] )                                                                                                   
            (.+)                                (?# bundle name [4] )                                                                                                                                                 
            \s+ .+ \(.+\) \s*                   (?# the versions--generally "??? [???]" )                                                                                                                             
            \<?([[:xdigit:]]{32})?\>?           (?# possible UUID [5] )                                                                                                                                               
            \s* (\/.*)\s*$                      (?# first fwdslash to end we hope is path [6] )                                                                                                                       
            ';
        %captures = ( 'base' => \$1, 'extent' => \$2, 'plus' => \$3,
                      'bundlename' => \$4, 'uuid' => \$5, 'path' => \$6);
    }
    elsif($report_version == 104) { # Kirkwood                                                                                                                                                                    
        $pat = '                                                                                                                                                                                              
            ^\s* (\w+) \s* \- \s* (\w+) \s*     (?# the range base and extent [1,2] )                                                                                                                                 
            (\+)?                               (?# the application may have a + in front of the name [3] )                                                                                                   
            (.+)                                (?# bundle name [4] )                                                                                                                                                 
            \s+ ('.$architectures.') \s+        (?# the image arch [5] )
            \<?([[:xdigit:]]{32})?\>?           (?# possible UUID [6] )                                                                                                                                               
            \s* (\/.*)\s*$                      (?# first fwdslash to end we hope is path [7] )                                                                                                                       
            ';
        %captures = ( 'base' => \$1, 'extent' => \$2, 'plus' => \$3,
                      'bundlename' => \$4, 'arch' => \$5, 'uuid' => \$6,
                      'path' => \$7);
    }
    elsif($report_version == 6) { # TheRealKerni   
        $pat = '                                                                                                                                                                                              
            ^\s* (\w+) \s* \- \s* (\w+) \s*     (?# the range base and extent [1,2] )                                                                                                                                 
            (\+)?                               (?# the application may have a + in front of the name [3] )                                                                                                   
            (.+)                                (?# bundle name [4] )                                                                                                                                                 
            \s+ .+ \(.+\) \s*                   (?# the versions--generally "??? [???]" )                                                                                                                             
            \<?([^\s]{36})?\>?                  (?# possible UUID [5] )                                                                                                                                               
            \s* (\/.*)\s*$                      (?# first fwdslash to end we hope is path [6] )                                                                                                                       
            ';
        %captures = ( 'base' => \$1, 'extent' => \$2, 'plus' => \$3,
                      'bundlename' => \$4, 'uuid' => \$5, 'path' => \$6);
    }
    elsif($report_version == 9) { # TheRealKerni   
        $pat = '                                                                                                                                                                                              
            ^\s* (\w+) \s* \- \s* (\w+) \s*     (?# the range base and extent [1,2] )                                                                                                                                 
            (\+)?                               (?# the application may have a + in front of the name [3] )                                                                                                   
            (.+)                                (?# bundle name [4] )                                                                                                                                                 
            \s+ \(.+\) \s*                      (?# the versions--generally "??? [???]" )                                                                                                                             
            \<?([^\s]{36})?\>?                  (?# possible UUID [5] )                                                                                                                                               
            \s* (\/.*)\s*$                      (?# first fwdslash to end we hope is path [6] )                                                                                                                       
            ';
        %captures = ( 'base' => \$1, 'extent' => \$2, 'plus' => \$3,
                      'bundlename' => \$4, 'uuid' => \$5, 'path' => \$6);
    }
    
    for my $line (@lines) {
        next if $line =~ /PEF binary:/; # ignore these
        
        $line =~ s/(&(\w+);?)/$entity2char{$2} || $1/eg;
        
        if ($line =~ /$pat/ox) {
        
            # Dereference references 
            my %image;
            while((my $key, my $val) = each(%captures)) {
                $image{$key} = ${$captures{$key}} || '';
                #print "image{$key} = $image{$key}\n";
            }
        
            if ($report_version == 6 || $report_version == 9) { # TheRealKerni 
                $image{uuid} =~ /(.{8})[-](.{4})[-](.{4})[-](.{4})[-](.{12})/;
                $image{uuid} = "$1$2$3$4$5";
            }
		
            $image{uuid} = lc $image{uuid};
            $image{arch} = $image{arch} || $default_arch;
        
            # Just take the first instance.  That tends to be the app.
            my $bundlename = $image{bundlename};
            $app = $bundlename if (!defined $app && defined $image{plus} && length $image{plus});

            # frameworks and apps (and whatever) may share the same name, so disambiguate
            if ( defined($images{$bundlename}) ) {
                # follow the chain of hash items until the end
                my $nextIDKey = $bundlename;
                while ( length($nextIDKey) ) {
                    last if ( !length($images{$nextIDKey}{nextID}) );
                    $nextIDKey = $images{$nextIDKey}{nextID};
                }

                # add ourselves to that chain
                $images{$nextIDKey}{nextID} = $image{base};

                # and store under the key we just recorded
                $bundlename = $bundlename . $image{base};
            }

            # we are the end of the nextID chain
            $image{nextID} = "";

            $images{$bundlename} = \%image;
        }
    }
    
    return (\%images, $app);
}

# if this is actually a partial binary identifier we know about, then
# return the full name. else return undef.
my %_partial_cache = ();
sub resolve_partial_id {
    my ($bundle,$images) = @_;
    # is this partial? note: also stripping elipsis here
    return undef unless $bundle =~ s/^\.\.\.//;
    return $_partial_cache{$bundle} if exists $_partial_cache{$bundle};
    
    my $re = qr/\Q$bundle\E$/;
    for (keys %$images) { 
        if( /$re/ ) { 
            $_partial_cache{$bundle} = $_;
            return $_;
        }
    }
    return undef;
}

sub fixup_last_exception_backtrace {
    my ($log_ref,$exception,$images) = @_;
    my $repl = $exception;
    if ($exception =~ m/^.0x/) {
        my @lines = split / /, substr($exception, 1, length($exception)-2);
        my $counter = 0;
        $repl = "";
        for my $line (@lines) {
            my ($image,$image_base) = findImageByAddress($images, $line);
            my $offset = hex($line) - hex($image_base);
            my $formattedTrace = sprintf("%-3d %-30s\t0x%08x %s + %d", $counter, $image, hex($line), $image_base, $offset);
            $repl .= $formattedTrace . "\n";
            ++$counter;
        }
        $log_ref = replace_chunk($log_ref, $exception, $repl);
        # may need to do this a second time since there could be First throw call stack too
        $log_ref = replace_chunk($log_ref, $exception, $repl);
    }
    return ($log_ref, $repl);
}

#sub parse_last_exception_backtrace {
#    print STDERR "Parsing last exception backtrace\n" if $opt{v};
#    my ($backtrace,$images, $inHex) = @_;
#    my @lines = split /\n/,$backtrace;
#    
#    my %frames = ();
#    
#    # these two have to be parallel; we'll lookup by hex, and replace decimal if needed
#    my @hexAddr;
#    my @replAddr;
#    
#    for my $line (@lines) {
#        # end once we're done with the frames
#        last if $line =~ /\)/;
#        last if !length($line);
#        
#        if ($inHex && $line =~ /0x([[:xdigit:]]+)/) {
#            push @hexAddr, sprintf("0x%08s", $1);
#            push @replAddr, "0x".$1;
#        }
#        elsif ($line =~ /(\d+)/) {
#            push @hexAddr, sprintf("0x%08x", $1);
#            push @replAddr, $1;
#        }
#    }
#    
#    # we don't have a hint as to the binary assignment of these frames
#    # map_addresses will do it for us
#    return map_addresses(\@hexAddr,$images,\@replAddr);
#}

# returns an oddly-constructed hash:
#  'string-to-replace' => { bundle=>..., address=>... }
sub parse_backtrace {
    my ($backtrace,$images,$decrement) = @_;
    my @lines = split /\n/,$backtrace;
    
    my $is_first = 1;
    
    my %frames = ();
    for my $line (@lines) {
        if( $line =~ m{
            ^\d+ \s+     # stack frame number
            (\S.*?) \s+    # bundle id (1)
            ((0x\w+) \s+   # address (3)
            .*) \s* $    # current description, to be replaced (2)
        }x ) {
            my($bundle,$replace,$address) = ($1,$2,$3);
            #print STDERR "Parse_bt: $bundle,$replace,$address\n" if ($opt{v});
            
            # disambiguate within our hash of binaries
            $bundle = findImageByNameAndAddress($images, $bundle, $address);
            
            # skip unless we know about the image of this frame
            next unless 
            $$images{$bundle} or
            $bundle = resolve_partial_id($bundle,$images);
            
            my $raw_address = $address;
            if($decrement && !$is_first) {
                $address = sprintf("0x%X", (hex($address) & ~1) - 1);
            }
            
            $frames{$replace} = {
                'address' => $address,
                'raw_address' => $raw_address,
                'bundle'  => $bundle,
            };
            
            $is_first   = 0;
        }
        #        else { print "unable to parse backtrace line $line\n" }
    }
    
    return \%frames;
}

sub slurp_file {
    my ($file) = @_;
    my $data;
    my $fh;
    my $readingFromStdin = 0;
    
    local $/ = undef;
    
    # - or "" mean read from stdin, otherwise use the given filename
    if($file && $file ne '-') {
        open $fh,"<",$file or die "while reading $file, $! : ";
    } else {
        open $fh,"<&STDIN" or die "while readin STDIN, $! : ";
        $readingFromStdin = 1;
    }
    
    $data = <$fh>;
    
    
    # Replace DOS-style line endings
    $data =~ s/\r\n/\n/g;
    
    # Replace Mac-style line endings
    $data =~ s/\r/\n/g;
    
    # Replace "NO-BREAK SPACE" (these often get inserted when copying from Safari)
    # \xC2\xA0 == U+00A0
    $data =~ s/\xc2\xa0/ /g;
    
    close $fh or die $!;
    return \$data;
}

sub parse_OSVersion {
    my ($log_ref) = @_;
    my $section = parse_section($log_ref,'OS Version');
    if ( $section =~ /\s([0-9\.]+)\s+\(Build (\w+)/ ) {
        return ($1, $2)
    }
    if ( $section =~ /\s([0-9\.]+)\s+\((\w+)/ ) {
        return ($1, $2)
    }
    if ( $section =~ /\s([0-9\.]+)/ ) {
        return ($1, "")
    }
    die "Error: can't parse OS Version string $section";
}

sub parse_report_version {
    my ($log_ref) = @_;
    my $version = parse_section($log_ref,'Report Version');
    $version or return undef;
    $version =~ /(\d+)/;
    return $1;
}
sub findImageByAddress {
    my ($images,$address) = @_;
    my $image;
    
    for $image (values %$images) {
        if ( hex($address) >= hex($$image{base}) && hex($address) <= hex($$image{extent}) )
        {
            return ($$image{bundlename},$$image{base});
        }
    }
    
    print STDERR "Unable to map $address\n" if $opt{v};
    
    return undef;
}

sub findImageByNameAndAddress {
    my ($images,$bundle,$address) = @_;
    my $key = $bundle;
    
    #print STDERR "findImageByNameAndAddress($bundle,$address) ... ";
    
    my $binary = $$images{$bundle};
    
    while($$binary{nextID} && length($$binary{nextID}) ) {
        last if ( hex($address) >= hex($$binary{base}) && hex($address) <= hex($$binary{extent}) );
        
        $key = $key . $$binary{nextID};
        $binary = $$images{$key};
    }
    
    #print STDERR "$key\n";
    return $key;
}

sub prune_used_images {
    my ($images,$bt) = @_;
    
    # make a list of images actually used in backtrace
    my $images_used = {};
    for(values %$bt) {
        #print STDERR "Pruning: $images, $$_{bundle}, $$_{address}\n" if ($opt{v});
        my $imagename = findImageByNameAndAddress($images, $$_{bundle}, $$_{address});
        $$images_used{$imagename} = $$images{$imagename};
    }
    
    # overwrite the incoming image list with that;
    %$images = %$images_used; 
}

# fetch symbolled binaries
#   array of binary image ranges and names
#   the OS build
#   the name of the crashed program
#    undef
#   array of possible directories to locate symboled files in
sub fetch_symbolled_binaries {
    
    print STDERR "Finding Symbols:\n" if $opt{v};
    
    my $pre = "."; # used in formatting progress output
    my $post = sprintf "\033[K"; # vt100 code to clear from cursor to end of line
    
    my ($images,$build,$bundle,@extra_search_paths) = @_;
    
    # fetch paths to symbolled binaries. or ignore that lib if we can't
    # find it
    for my $b (keys %$images) {
        my $lib = $$images{$b};
        
        print STDERR "\r${pre}fetching symbol file for $b$post" if $opt{v};
        $pre .= ".";
        
        
        my $symbol = $$lib{symbol};
        unless($symbol) {
            ($symbol) = getSymbolPathFor($$lib{path},$build,$$lib{uuid},$$lib{arch},@extra_search_paths);
            if($symbol) { 
                $$lib{symbol} = $symbol;
            }
            else { 
                delete $$images{$b};
                next;
            }
        }
        
        print STDERR "\r${pre}checking address range for $b$post" if $opt{v};
        $pre .= ".";
        
        # check for sliding. set slide offset if so
        open my($ph),"-|", "$size -m -l -x '$symbol'" or die $!;
        my $real_base = ( 
        grep { $_ } 
        map { (/_TEXT.*vmaddr\s+(\w+)/)[0] } <$ph> 
        )[0];
        close $ph;
        if ($?) {
            # call to size failed.  Don't use this image in symbolication; don't die
            delete $$images{$b};
            print STDERR "Error in symbol file for $symbol\n"; # and log it
            next;
        }
        
        if($$lib{base} ne $real_base) {
            $$lib{slide} =  hex($real_base) - hex($$lib{base});
        }
    }
    print STDERR "\rdone.$post\n" if $opt{v};
    print STDERR "\r$post" if $opt{v};
    print STDERR keys(%$images) . " binary images were found.\n" if $opt{v};
}

# run atos
sub symbolize_frames {
    my ($images,$bt) = @_;
    
    # create mapping of framework => address => bt frame (adjust for slid)
    # and for framework => arch
    my %frames_to_lookup = ();
    my %arch_map = ();
    my %base_map = ();
    
    for my $k (keys %$bt) {
        my $frame = $$bt{$k};
        my $lib = $$images{$$frame{bundle}};
        unless($lib) {
            # don't know about it, can't symbol
            # should have already been warned about this!
            # print "Skipping unknown $$frame{bundle}\n";
            delete $$bt{$k};
            next;
        }
        
        # list of address to lookup, mapped to the frame object, for
        # each library
        $frames_to_lookup{$$lib{symbol}}{$$frame{address}} = $frame;
        $arch_map{$$lib{symbol}} = $$lib{arch};
        $base_map{$$lib{symbol}} = $$lib{base};
    }
    
    # run atos for each library
    while(my($symbol,$frames) = each(%frames_to_lookup)) {
        # escape the symbol path if it contains single quotes
        my $escapedSymbol = $symbol;
        $escapedSymbol =~ s/\'/\'\\'\'/g;
        
        # run atos with the addresses and binary files we just gathered
        my $arch = $arch_map{$symbol};
        my $base = $base_map{$symbol};
        my $cmd = "$atos -arch $arch -l $base -o '$escapedSymbol' @{[ keys %$frames ]} | ";
        
        print STDERR "Running $cmd\n" if $opt{v};
        
        open my($ph),$cmd or die $!;
        my @symbolled_frames = map { chomp; $_ } <$ph>;
        close $ph or die $!;
        
        my $references = 0;
        
        foreach my $symbolled_frame (@symbolled_frames) {
            
            $symbolled_frame =~ s/\s*\(in .*?\)//; # clean up -- don't need to repeat the lib here
            
            # find the correct frame -- the order should match since we got the address list with keys
            my ($k,$frame) = each(%$frames);
            
            if ( $symbolled_frame !~ /^\d/ ) {
                # only symbolicate if we fetched something other than an address
                #re-increment any offset that we had to artifically decrement
                if($$frame{raw_address} ne $$frame{address}) {
                    $symbolled_frame =~ s|(.+ \+) (\d+)|$1." ".($2 + 1)|e;
                }
                
                $$frame{symbolled} = $symbolled_frame;
                $references++;
            }
            
        }
        
        if ( $references == 0 ) {
            print STDERR "## Warning: Unable to symbolicate from required binary: $symbol\n";
        }
    }
    
    # just run through and remove elements for which we didn't find a
    # new mapping:
    while(my($k,$v) = each(%$bt)) {
        delete $$bt{$k} unless defined $$v{symbolled};
    }
}

# run the final regex to symbolize the log
sub replace_symbolized_frames {
    my ($log_ref,$bt)  = @_; 
    my $re = join "|" , map { quotemeta } keys %$bt;
    
    my $log = $$log_ref;
    $log =~ s#$re#
    my $frame = $$bt{$&};
    $$frame{raw_address} ." ". $$frame{symbolled};
    #esg;
    
    $log =~ s/(&(\w+);?)/$entity2char{$2} || $1/eg;
    
    return \$log;
}

sub replace_chunk {
    my ($log_ref,$old,$new) = @_;
    my $log = $$log_ref;
    my $re = quotemeta $old;
    $log =~ s/$re/$new/;
    return \$log;
}

#############

sub output_log($) {
  my ($log_ref)  = @_;
  
  if($opt{'o'}) {
    close STDOUT;
    open STDOUT, '>', $opt{'o'};
  }
  
  print $$log_ref;
}

#############

sub symbolicate_log {
    my ($file,@extra_search_paths) = @_;
    
    print STDERR "Symbolicating...\n" if ( $opt{v} );
    
    my $log_ref = slurp_file($file);
    
    print STDERR length($$log_ref)." characters read.\n" if ( $opt{v} );
    
    # get the version number
    my $report_version = parse_report_version($log_ref);
    $report_version or die "No crash report version in $file";
    
    # read the binary images
    my ($images,$first_bundle) = parse_images($log_ref, $report_version);
    
    if ( $opt{v} ) {
        print STDERR keys(%$images) . " binary images referenced:\n";
        foreach (keys(%$images)) {
            print STDERR $_;
            print STDERR "\t\t(";
            print STDERR $$images{$_}{path};
            print STDERR ")\n";
        }
        print "\n";
    }
    
    my $bt = {};
    my $threads = parse_sections($log_ref,'Thread\s+\d+\s?(Highlighted|Crashed)?',multiline=>1);
    for my $thread (values %$threads) {
        # merge all of the frames from all backtraces into one
        # collection
        my $b = parse_backtrace($thread,$images,0);
        @$bt{keys %$b} = values %$b;
    }
    
    # extract build
    my ($version, $build) = parse_OSVersion($log_ref);
    print STDERR "OS Version $version Build $build\n" if $opt{v};
    
    my $exception = parse_section($log_ref,'Last Exception Backtrace', multiline=>1);
    if (defined $exception) {
        ($log_ref, $exception) = fixup_last_exception_backtrace($log_ref, $exception, $images);
        #my $e = parse_last_exception_backtrace($exception, $images, 1);
        my $e = parse_backtrace($exception, $images,1);
        
        # treat these frames in the same was as any thread
        @$bt{keys %$e} = values %$e;
    }
    
    # sort out just the images needed for this backtrace
    prune_used_images($images,$bt);
    if ( $opt{v} ) {
        print STDERR keys(%$images) . " binary images remain after pruning:\n";
        foreach my $junk (keys(%$images)) {
            print STDERR $junk;
            print STDERR ", ";
        }
        print STDERR "\n";
    } 
    
    @extra_search_paths = (@extra_search_paths, getSymbolDirPaths($version, $build));

    fetch_symbolled_binaries($images,$build,$first_bundle,@extra_search_paths);
    
    # If we didn't get *any* symbolled binaries, just print out the original crash log.
    my $imageCount = keys(%$images);
    if ($imageCount == 0) {
        output_log($log_ref);
        return;
    }
        
    # run atos
    symbolize_frames($images,$bt);
    
    if(keys %$bt) {
        # run our fancy regex
        my $new_log = replace_symbolized_frames($log_ref,$bt);
        output_log($new_log);
    } else {
        #There were no symbols found
        print STDERR "No symbolic information found\n";
        output_log($log_ref);
    }
}
