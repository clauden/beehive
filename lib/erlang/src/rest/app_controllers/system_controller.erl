%%%-------------------------------------------------------------------
%%% File    : system_controller.erl
%%% Author  : Ari Lerner
%%% Description : 
%%%
%%% Created :  Thu Dec 31 12:52:24 PST 2009
%%%-------------------------------------------------------------------

-module (system_controller).
-include ("http.hrl").
-export ([get/2, post/2, put/2, delete/2]).

get(_, _Data) -> 
  {struct, [{"beehive", ?BINIFY(["routes"])}]}.

post(["_reload"], Data) ->
  auth_utils:run_if_admin(fun(_) ->
    misc_utils:reload_all()
  end, Data);
post(_Path, _Data) -> error("unhandled").
put(_Path, _Data) -> error("unhandled").
delete(_Path, _Data) -> error("unhandled").

error(Msg) ->
  {struct, [{error, misc_utils:to_bin(Msg)}]}.