#!/usr/bin/perl
#############################################################################################
#
#   Plesk Event Handller Tool for Creating vhost.conf in User Space
#       Copyright (C) 2012 MATSUMOTO, Ryosuke
#
#   This Code was written by matsumoto_r                 in 2012/05/18 -
#
#   Usage:
#       /usr/local/sbin/add-vhost-conf.pl
#
#############################################################################################
#
# Change Log
#
# 2012/05/18 matsumoto_r first release
#
#############################################################################################

use strict;
use warnings;
use File::Spec;
use File::Basename;
use Getopt::Long;
use File::Compare;
use DirHandle;

our $VERSION     = '0.01';
our $SCRIPT      = basename($0);

my ($type, $domain, $subdomain, $user);

GetOptions(

    "--type|t=s"        =>  \$type,
    "--domain|d=s"      =>  \$domain,
    "--subdomain|s=s"   =>  \$subdomain,
    "--user|u=s"        =>  \$user,
    "--help"            =>  \&help,
    "--version"         =>  \&version,
);

&help if !defined $type;
&help if !defined $domain && !defined $subdomain;
$subdomain = "nothing" if !defined $subdomain;

my $vroot           = File::Spec->catfile("/var", "www", "vhosts");

our $USER_CONF      = File::Spec->catfile("conf", "vhost.conf");
our $USER_SSL_CONF  = File::Spec->catfile("conf", "vhost_ssl.conf");
our $DOMAIN_UPDATE  = (!defined $user)  ?   1   :   0;
our $SUEXEC_USER    = $user if defined $user;
our $SUEXEC_GROUP   = "suexegroup";
our $TUNING_CONF    = File::Spec->catfile($vroot, $domain, "conf", "tuning.conf");
our $CONFIG_TYPE    = $type;

my $TYPE_MAP = {

    domain      =>  {
                        command         =>  \&set_domain_config,
                        subdomain_dir   =>  File::Spec->catfile($vroot, $domain, "subdomains"),
                        httpconf        =>  File::Spec->catfile($vroot, $domain, $USER_CONF),
                        httpsconf       =>  File::Spec->catfile($vroot, $domain, $USER_SSL_CONF),
                    },

    subdomain   =>  {
                        command         =>  \&set_config,
                        httpconf        =>  File::Spec->catfile($vroot, $domain, "subdomains", $subdomain, $USER_CONF),
                        httpsconf       =>  File::Spec->catfile($vroot, $domain, "subdomains", $subdomain, $USER_SSL_CONF),
                    },

};

&help if !exists $TYPE_MAP->{$CONFIG_TYPE};

&domain_update_only if $DOMAIN_UPDATE;

$TYPE_MAP->{$type}->{command}->($TYPE_MAP->{$CONFIG_TYPE}->{httpconf}, "http");
$TYPE_MAP->{$type}->{command}->($TYPE_MAP->{$CONFIG_TYPE}->{httpsconf}, "https");
&file_write($TUNING_CONF, "w", "") if !-f $TUNING_CONF;

exit 0;

### sub routines ###

sub domain_update_only {

    my $target_httpconf  = $TYPE_MAP->{$CONFIG_TYPE}->{httpconf};
    my $target_httpsconf = $TYPE_MAP->{$CONFIG_TYPE}->{httpsconf};

    foreach my $dir (&get_subdomain($CONFIG_TYPE)) {

        my $target_sub_httpconf  = File::Spec->catfile($TYPE_MAP->{$CONFIG_TYPE}->{subdomain_dir}, $dir, $USER_CONF);
        my $target_sub_httpsconf = File::Spec->catfile($TYPE_MAP->{$CONFIG_TYPE}->{subdomain_dir}, $dir, $USER_SSL_CONF);

        &change_tuning_conf_path($target_sub_httpconf) if -f $target_sub_httpconf;
        &change_tuning_conf_path($target_sub_httpsconf) if -f $target_sub_httpsconf;

    }
    
    &change_tuning_conf_path($target_httpconf) if -f $target_httpconf;
    &change_tuning_conf_path($target_httpsconf) if -f $target_httpsconf;

    exit 0;
}

sub change_tuning_conf_path {

    my $target_conf = shift;

    my @config = &file_read($target_conf);
    my $config_lines;

    foreach my $line (@config) {
        $line = "include $TUNING_CONF\n" if $line =~ /^include/;
        $config_lines .= $line;
    }

    &file_write($target_conf, "w", $config_lines);   
}

sub set_domain_config {

    my ($config_file, $protocol) = @_;

    foreach my $dir (&get_subdomain($CONFIG_TYPE)) {

        my $taget_httpconf  = File::Spec->catfile($TYPE_MAP->{$CONFIG_TYPE}->{subdomain_dir}, $dir, $USER_CONF);
        my $taget_httpsconf = File::Spec->catfile($TYPE_MAP->{$CONFIG_TYPE}->{subdomain_dir}, $dir, $USER_SSL_CONF);

        &set_config($taget_httpconf) if $protocol eq "http" && !compare($config_file, $taget_httpconf);
        &set_config($taget_httpsconf) if $protocol eq "https" && !compare($config_file, $taget_httpsconf);

    }
    
    &set_config($config_file);

}

sub set_config {

    my $conf_file = shift;

    my $conf        = <<CONF;
SuexecUserGroup         $SUEXEC_USER $SUEXEC_GROUP

include $TUNING_CONF

CONF

    &file_write($conf_file, "w", $conf);

}

sub get_subdomain {
    
    my @subdomains;
    my $dh = DirHandle->new($TYPE_MAP->{$CONFIG_TYPE}->{subdomain_dir}) or exit 1;

    while (my $dir = $dh->read) {
        next if $dir =~ /^\.$/ || $dir =~ /^\.\.$/;
        push @subdomains, $dir;
    }

    $dh->close;

    return @subdomains;

}

sub file_read {

    my $read_file = shift;

    open(HFILE, "< $read_file") or die "can not open file: $read_file";
    my @contents = <HFILE>;
    close HFILE;

    return @contents;
}

sub file_write {

    my ($file, $type, $str)  = @_;

    my $WRITE_MAP = {

        a   =>  ">>",
        w   =>  ">",

    };

    exit 1 if !exists $WRITE_MAP->{$type};

    open(FH, "$WRITE_MAP->{$type} $file") or exit 1;
    print FH "$str";
    close(FH);

}

sub help {
    print <<USAGE;

    usage: ./$SCRIPT --type|-t TYPE --domain|-d DOMAIN [--subdomain|-s SUBDOMAIN] --user|-u USER

        TYPE:   subdomain|domain

USAGE
    exit(1);
}

sub version {

    print <<VERSION;

    Version: $SCRIPT-$VERSION

VERSION
    exit(1);

}
