%%%-------------------------------------------------------------------
%%% File    : babysitter_app.erl
%%% Author  : Ari Lerner
%%% Description : 
%%%
%%% Created :  Thu Dec 24 15:07:11 PST 2009
%%%-------------------------------------------------------------------

-module (babysitter_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> 
  % lists:map(fun(A) ->
  %   io:format("Starting ~p...", [A]),
  %   A:start([])
  % end, [exec]),
  exec:start_link([{alarm, 20},{debug, true}]),
  babysitter_sup:start_link().

stop(_State) -> 
  io:format("Stopping babysitter_app...~n"),
  ok.
