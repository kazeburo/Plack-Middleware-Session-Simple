package Plack::Middleware::Session::Simple;

use 5.008005;
use strict;
use warnings;
use parent qw/Plack::Middleware/;
use Storable qw//;
use Digest::SHA ();
use Cookie::Baker;
use Plack::Util;
use Scalar::Util qw/blessed/;
use List::Util qw//;
use Plack::Util::Accessor qw/
    store
    secret
    cookie_name
    path
    domain
    expires
    secure
    httponly
/;

our $VERSION = "0.01";

sub prepare_app {
    my $self = shift;

    my $store = $self->store;
    die('store require get, set and remove method.')
        unless blessed $store
            && $store->can('get')
            && $store->can('set')
            && $store->can('remove');

    $self->cookie_name('simple_session') unless $self->cookie_name;
    $self->path('/') unless defined $self->path;
    
    if ( !defined $self->secret ) {
        warn 'secret is undefineded use "__FILE__" for this time. Highly recommended to use set your secret string';
        $self->secret(__FILE__);
    }
}

sub call {
    my ($self,$env) = @_;

    my($id, $session) = $self->get_session($env);

    my $tied;
    if ($id && $session) {
        $tied = tie my %session, 
            'Plack::Middleware::Session::Simple::Session', %$session;
        $env->{'psgix.session'} = \%session;
        $env->{'psgix.session.options'} = {
            id => $id,
        };
    } else {
        my $id = $self->generate_id();
        $tied = tie my %session, 
            'Plack::Middleware::Session::Simple::Session';
        $env->{'psgix.session'} = \%session;
        $env->{'psgix.session.options'} = {
            id => $id,
            new_session => 1,
        };
    }

    my $res = $self->app->($env);

    $self->response_cb(
        $res, sub {
            $self->finalize($env, $_[0], $tied)
        }
    );
}

sub get_session {
    my ($self, $env) = @_;
    my $cookie = crush_cookie($env->{HTTP_COOKIE} || '')->{$self->cookie_name};
    return unless defined $cookie;
    return unless $cookie =~ m!\A[0-9a-f]{37}!;

    my $id = substr($cookie,0,31);
    my $chk = substr($cookie,31,6);

    my $has_key = List::Util::first {
        $chk eq substr(Digest::SHA::hmac_sha1_hex($id.$_,$self->secret),0,6)
    } (1,0);
    return ($id, {}) if $has_key == 0;
    my $session = $self->store->get($id) or return;
    return ($id, $session);
}

sub generate_id {
    my ($self) = @_;
    substr(Digest::SHA::sha1_hex(rand() . $$ . {} . time),int(rand(4)),31);
}

sub generate_chk {
    my ($self, $id, $has_key) = @_;
    $has_key = $has_key ? '1' : '0';
    substr(Digest::SHA::hmac_sha1_hex($id.$has_key,$self->secret),0,6);
}

sub finalize {
    my ($self, $env, $res, $session) = @_;
    my $options = $env->{'psgix.session.options'};
    my $new_session = delete $options->{new_session};

    my $need_store;
    if ( $session->is_dirty || $options->{expire} || $options->{change_id}) {
        $need_store = 1;
    }
    $need_store = 0 if $options->{no_store};

    my $set_cookie;
    if ( $new_session || $session->is_vary || $options->{expire} || $options->{change_id}) {
        $set_cookie = 1;
    }

    if ( $need_store ) {
        if ($options->{expire}) {
            $self->store->remove($options->{id});
        } elsif ($options->{change_id}) {
            $self->store->remove($options->{id});
            ($options->{id}) = $self->generate_id();
            $self->store->set($options->{id}, $session->untie);
        } else {
            $self->store->set($options->{id}, $session->untie);
        }
    }

    if ( $set_cookie ) {
        if ($options->{expire}) {
            $self->_set_cookie(
                $options->{id} . $self->generate_chk($options->{id},0),
                $res, %$options, expires => 'now'); 
        } else {
            $self->_set_cookie(
                $options->{id} . $self->generate_chk($options->{id},$session->has_key),
                $res, %$options); 
        }
    }
}

sub _set_cookie {
    my($self, $id, $res, %options) = @_;

    delete $options{id};

    $options{path}     = $self->path || '/' if !exists $options{path};
    $options{domain}   = $self->domain      if !exists $options{domain} && defined $self->domain;
    $options{secure}   = $self->secure      if !exists $options{secure} && defined $self->secure;
    $options{httponly} = $self->httponly    if !exists $options{httponly} && defined $self->httponly;

    if (!exists $options{expires} && defined $self->expires) {
        $options{expires} = $self->expires;
    }

    my $cookie = bake_cookie( 
        $self->cookie_name, {
            value => $id,
            %options,
        }
    );
    Plack::Util::header_push($res->[1], 'Set-Cookie', $cookie);
}

1;

package Plack::Middleware::Session::Simple::Session;

use strict;
use warnings;
use Tie::Hash;
use base qw/Tie::ExtraHash/;

sub TIEHASH {
    my $class = shift;
    bless [{@_},0, scalar @_], $class;
}

sub STORE {
    my $self = shift;
    $self->[1]++;
    $self->SUPER::STORE(@_);
}

sub DELETE {
    my $self = shift;
    $self->[1]++;
    $self->SUPER::DELETE(@_);
}

sub CLEAR {
    my $self = shift;
    $self->[1]++;
    $self->SUPER::CLEAR(@_);
}

sub is_dirty {
    $_[0]->[1];
}

sub untie : method  {
    $_[0]->[0];
}

sub has_key {
    scalar keys %{$_[0]->[0]};
} 

sub is_vary {
    $_[0]->[2] == 0 && keys %{$_[0]->[0]} > 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

Plack::Middleware::Session::Simple - Make Session Simple

=head1 SYNOPSIS

    use Plack::Builder;
    use Cache::Memcached::Fast;

    my $app = sub {
        my $env = shift;
        my $counter = $env->{'psgix.session'}->{counter}++;
        [200,[], ["counter => $counter"]];
    };
    
    builder {
        enable 'Session::Simple',
            store => Cache::Memcached::Fast->new({servers=>[..]}),
            cookie_name => 'myapp_session';
        $app
    };


=head1 DESCRIPTION

Plack::Middleware::Session::Simple is a yet another session management module.
This middleware supports psgix.session and psgi.session.options. 
Plack::Middleware::Session::Simple has compatibility with Plack::Middleware::Session 
and you can reduce unnecessary accessing to store and Set-Cookie header.

This module uses Cookie to keep session state. does not support URI based session state.

=head1 OPTIONS

=over 4

=item store

object instance that has get, set, and remove methods.

=item cookie_name

This is the name of the session key, it defaults to 'simple_session'.

=item secret

Server side secret to sign the session data using HMAC SHA1. Defaults to __FILE__.
But strongly recommended to set your own secret string.

=item path

Path of the cookie, this defaults to "/";

=item domain

Domain of the cookie, if nothing is supplied then it will not be included in the cookie.

=item expires

Cookie's expires date time. several formats are supported. see L<Cookie::Baker> for details.
if nothing is supplied then it will not be included in the cookie, which means the session expires per browser session.

=item secure

Secure flag for the cookie, if nothing is supplied then it will not be included in the cookie.

=item httponly

HttpOnly flag for the cookie, if nothing is supplied then it will not be included in the cookie.

=back 

=head1 LICENSE

Copyright (C) Masahiro Nagano.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo@gmail.comE<gt>

=cut

