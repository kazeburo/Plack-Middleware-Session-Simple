package MyApp;

use strict;
use warnings;
use Kossy;
use Log::StringFormatter;

get '/' => sub {
    my ($self, $c) = @_;
    if ( my $un = $c->req->env->{'psgix.session'}->{username} ) {
        return "hello $un";
    }
    return "ok";
};

get '/counter' => sub {
    my ($self, $c) = @_;
    my $counter = $c->req->env->{'psgix.session'}->{counter}++;
    return "counter => $counter";
};

get '/login' => sub {
    my ($self, $c) = @_;
    $c->req->env->{'psgix.session'}->{username} = "foo";
    return "login";
};

get '/logout' => sub {
    my ($self, $c) = @_;
    $c->req->env->{'psgix.session.options'}->{expire} = 1
        if $c->req->env->{'psgix.session'}->{username};
    return "logout";
};

package main;


use Plack::Builder;
use Cache::Memcached::Fast;

builder {
    enable 'Session::Simple',
        store => Cache::Memcached::Fast->new({servers=>[qw/127.0.0.1:11211/]});
    MyApp->psgi
};

