-define(LOG(LogLevel, LogFormat, LogArgs), 
        % try
        case event_manager:notify({log, LogLevel, LogFormat, LogArgs, ?FILE, ?LINE}) of
          ok -> ok;
          {error, _} -> throw({error, logging_exception})
        end
        ).

-ifdef (debug).
-define (BENCHMARK_LOG (Msg, Mod, Fun, Args), fun() ->
  {Time, Value} = timer:tc(Mod, Fun, Args),
  ?LOG(benchmark, "~p microseconds ~p ~p:~p/~p", [Time, Msg, Mod, Fun, erlang:length(Args)]),
  Value
end()).
-else.
-define (BENCHMARK_LOG (_Msg, Mod, Fun, Args),
  erlang:apply(Mod, Fun, Args)).
-endif.

% Root of the modules
-define (BH_ROOT, fun() ->
  filename:dirname(filename:dirname(code:which(?MODULE)))
  end()).

% Defined beehive home path
-define (BEEHIVE_HOME_DIR, fun() ->
  case os:getenv("BEEHIVE_HOME") of
    false -> "/var/lib/beehive";
    E -> E
  end
end()).

-define (USER_OR_BH (List), bh_file_utils:relative_or_abs_path(List)).
-define (BH_RELATIVE_DIR (List), filename:join([?BEEHIVE_HOME_DIR, List])).

% Figure this out... Hm
-define (SHELL_SCRIPTS_DIR, ?USER_OR_BH("shell_templates")).
-define (SHELL_SCRIPT_PATH (Name), filename:join([?SHELL_SCRIPTS_DIR, lists:append([Name, ".sh"])])).
-define (SHELL_SCRIPT (Name), fun() ->
  case file:read_file(?SHELL_SCRIPT_PATH(Name)) of
    {ok, Binary} -> erlang:binary_to_list(Binary);
    {error, Reason} -> 
      ?LOG(error, "Could not file shell_script named: ~p", [?SHELL_SCRIPT_PATH(Name)]),
      throw({error, shell_script, Reason})
    end
 end()
).
-define (TEMPLATE_SHELL_SCRIPT (Name, Params), fun() -> string_utils:template_command_string(?SHELL_SCRIPT(Name), Params) end()).
-define (TEMPLATE_SHELL_SCRIPT_PARSED (Name, Params), misc_utils:shell_fox(Name, Params)).

-define (APP_TEMPLATE_SHELL_SCRIPT_PARSED (Name, Proplists, Env), app_utils:app_template_parsed(Name, Proplists, Env)).