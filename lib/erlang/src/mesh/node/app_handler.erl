%%%-------------------------------------------------------------------
%%% File    : app_handler.erl
%%% Author  : Ari Lerner
%%% Description : 
%%%
%%% Created :  Thu Nov 19 12:45:16 PST 2009
%%%-------------------------------------------------------------------

-module (app_handler).
-include ("beehive.hrl").
-include ("common.hrl").
-behaviour(gen_server).

%% API
-export([
  start_link/0,
  stop/0,
  start_new_instance/4,
  stop_instance/3, stop_app/2,
  can_deploy_new_app/0,
  has_app_named/1
]).


%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
  max_bees             % maximum number of bees on this host
}).
-define(SERVER, ?MODULE).

-define (STORAGE_SRV, bh_storage_srv).

-define (TAB_ID_TO_BEE, 'id_to_bee_table').
-define (TAB_NAME_TO_BEE, 'name_to_bee_table').

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?SERVER, {stop}).
  
can_deploy_new_app() ->
  gen_server:call(?SERVER, {can_deploy_new_app}).
  
start_new_instance(App, Sha, AppLauncher, From) ->
  gen_server:call(?SERVER, {start_new_instance, App, Sha, AppLauncher, From}).

stop_instance(Bee, App, From) ->
  gen_server:call(?SERVER, {stop_instance, Bee, App, From}).

has_app_named(Name) ->
  gen_server:call(?SERVER, {has_app_named, Name}).
  
stop_app(App, From) ->
  gen_server:cast(?SERVER, {stop_app, App, From}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
  process_flag(trap_exit, true),
  
  Opts = [named_table, set],
  ets:new(?TAB_ID_TO_BEE, Opts),
  ets:new(?TAB_NAME_TO_BEE, Opts),
  
  MaxBackends     = ?MAX_BACKENDS_PER_HOST,
  
  {ok, #state{
    max_bees = MaxBackends
  }}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%-------------------------------------------------------------------- 
handle_call({start_new_instance, App, Sha, AppLauncher, From}, _From, State) ->
  
  Port = bh_host:unused_port(),
  
  % Then start it :)
  ?LOG(debug, "internal_start_new_instance: ~p, ~p, ~p, ~p, ~p~n", [App, Sha, Port, AppLauncher, From]),
  internal_start_new_instance(App, Sha, Port, AppLauncher, From),
  {reply, ok, State};

handle_call({stop_instance, Backend, App, From}, _From, State) ->
  internal_stop_instance(Backend, App, From),
  {reply, ok, State};

handle_call({has_app_named, Name}, _From, State) ->
  Reply = case ets:lookup(?TAB_NAME_TO_BEE, Name) of
      [{Name, _Bee}] -> true;
      _ -> false
    end,
  {reply, Reply, State};

% Check if this node can deploy a new application or not
handle_call({can_deploy_new_app}, _From, #state{max_bees = Max} = State) ->
  Curr = ets:match(?TAB_NAME_TO_BEE, '$1'),
  Reply = (length(Curr) < Max),
  {reply, Reply, State};
handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
% Good spot for optimization
handle_cast({stop_app, App, _From}, State) ->
  AppBees = lists:flatten(ets:match(?TAB_NAME_TO_BEE, {App#app.name, '$1'})),
  
  io:format("Terminating AppBees: ~p~n", [AppBees]),  
  {noreply, State};
  
handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({'EXIT', Pid, Reason}, State) ->
  ?LOG(info, "Pid exited: ~p because ~p", [Pid, Reason]),
  {noreply, handle_pid_exit(Pid, Reason, State)};
handle_info({port_closed, Pid, 0}, State) ->
  ?LOG(info, "Port closed: ~p", [Pid]),
  {noreply, State};
handle_info({data, _Data}, State) ->
  % io:format("Received data from a port: ~p~n", [Data]),
  {noreply, State};
handle_info({stop}, State) ->
  {stop, normal, State};
handle_info({port_exited,Port,Pid}, State) ->
  % Do something with this...
  io:format("Port process exited: ~p, ~p~n", [Port, Pid]),
  {noreply, State};
handle_info(Info, State) ->
  ?LOG(info, "~p caught info: ~p", [?MODULE, Info]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
% Start new instance
internal_start_new_instance(App, Sha, Port, AppLauncher, From) ->
  case find_and_transfer_bee(App, Sha) of
    {ok, Node, LocalPath} ->
      Proplists = [{sha, Sha}, {port, Port}, {bee_image, LocalPath}, {storage_node, Node}],
      initialize_application(App, Proplists, AppLauncher, From);
    E -> 
      io:format("Error: ~p~n", [E]),
      E
  end.

% Initialize the node
initialize_application(#app{template = Template} = App, PropLists, AppLauncher, _From) ->
  Sha = proplists:get_value(sha, PropLists),
  Port = proplists:get_value(port, PropLists),
  ImagePath = proplists:get_value(bee_image, PropLists),
  StorageNode = proplists:get_value(storage_node, PropLists),
  
  Host = bh_host:myip(),
  Id = {App#app.name, Host, Port},
  StartedAt = date_util:now_to_seconds(),
  
  Vars = [
    {"[[BEE_IMAGE]]", ImagePath},
    {"[[HOST_IP]]", Host},
    {"[[PORT]]", misc_utils:to_list(Port)},
    {"[[SHA]]", Sha},
    {"[[START_TIME]]", misc_utils:to_list(StartedAt)},
    {"[[APP_NAME]]", App#app.name}
  ],
  
  Env = [
    [lists:flatten(["SHA=\"", Sha, "\""])],
    [lists:flatten(["LOCAL_PORT=\"", misc_utils:to_list(Port), "\""])],
    [lists:flatten(["LOCAL_HOST=\"", Host, "\""])],
    [lists:flatten(["STARTED_AT=\"", misc_utils:to_list(StartedAt), "\""])],
    [lists:flatten(["APP_NAME=\"", App#app.name, "\""])],
    ["RACK_ENV=production"],
    ["PATH=$PATH:/usr/bin:/bin:/usr/local/bin"]
  ],
  
  StdOut = lists:flatten(["/var/log/beehive/", App#app.name, ".log"]),
  
  DefaultProps = [{env_vars, Env}, {image, ImagePath}, {stdout, StdOut}, {stderr, StdOut}, {files_count, "103"}],
  
  StartProplist = ?APP_TEMPLATE_SHELL_SCRIPT_PARSED(Template, Vars, DefaultProps),
  % AppRootPath = proplists:get_value(path, Proplist1),
  
  Bee  = #bee{
    id                      = Id,
    app_name                = App#app.name,
    host                    = Host,
    host_node               = node(self()),
    storage_node            = StorageNode,
    % path                    = AppRootPath,
    port                    = Port,
    status                  = pending,
    commit_hash             = Sha,
    start_time              = StartedAt
  },
  
  io:format("------ App handler using babysitter spawn_new: ~p~n", [StartProplist]),
  case babysitter:spawn_new(StartProplist, self()) of
    {ok, ProcessPid, SysPid} ->
      % Store the app in the local ets table
      NewBee = Bee#bee{pid = ProcessPid, os_pid = SysPid},
      ets:insert(?TAB_ID_TO_BEE, {Id, NewBee}),
      ets:insert(?TAB_NAME_TO_BEE, {App#app.name, NewBee}),
      
      AppLauncher ! {started_bee, NewBee},
      NewBee;
    Code ->
      AppLauncher ! {error, Code}
  end.

% Find and transfer the bee
find_and_transfer_bee(App, Sha) ->
  Nodes = lists:map(fun(N) -> node(N) end, node_manager:get_storage()),
  Path = next_free_honeycomb(App),
  LocalPath = filename:join([filename:absname(""), lists:append([Path, "/", "app.img"])]),
  ?LOG(info, "find_bee_on_storage_nodes: ~p:~p on nodes: ~p at Path: ~p and LocalPath: ~p", [App#app.name, Sha, Nodes, Path, LocalPath]),
  case find_bee_on_storage_nodes(App, Sha, Nodes) of
    {ok, Node, RemotePath} ->
      ?LOG(info, "find_bee_on_storage_nodes found on ~p at ~p", [Node, RemotePath]),
      slugger:get(Node, RemotePath, LocalPath),
      {ok, Node, LocalPath};
    E -> 
      ?LOG(info, "find_bee_on_storage_nodes returned ~p instead of something useful", [E]),
      E
  end.

% Look on the node and see if it has the 
find_bee_on_storage_nodes(App, _Sha, []) -> 
  % ?NOTIFY({app, app_not_squashed, Name}),
  ?LOG(info, "App not found: ~p", [App#app.name]),
  ?NOTIFY({app, updated, App}),
  {error, not_found};
find_bee_on_storage_nodes(App, Sha, [Node|Rest]) ->
  case rpc:call(Node, ?STORAGE_SRV, has_squashed_repos, [App, Sha]) of
    false -> find_bee_on_storage_nodes(App, Sha, Rest);
    Path -> 
      ?LOG(info, "Found bee (~p) on node: ~p at ~p", [App#app.name, Node, Path]),
      {ok, Node, Path}
  end.

% kill the instance of the application  
internal_stop_instance(#bee{id = Id, pid = PidPort, port = Port, host = Host} = _CalledBee, App, From) when is_record(App, app) ->  
  #bee{commit_hash = Sha} = Bee = bees:find_by_id(Id),
  ?LOG(debug, "internal_stop_instance: ~p and ~p", [Sha, App#app.name]),
  
  % Send a SIGHUP
  babysitter:stop_process(PidPort),
  
  case ets:lookup(?TAB_ID_TO_BEE, {App#app.name, Host, Port}) of
    [{Key, _B}] ->
      ets:delete(?TAB_NAME_TO_BEE, App#app.name),
      ets:delete(?TAB_ID_TO_BEE, Key);
    _ -> true
  end,
  From ! {bee_terminated, Bee}.

% Get a new honeycomb location for the new bee
next_free_honeycomb(App) ->
  BaseDir = config:search_for_application_value(squashed_storage, ?BH_RELATIVE_DIR("apps"), storage),
  UniqueName = apps:build_on_disk_app_name(App),
  {Proplists, _Status} = ?TEMPLATE_SHELL_SCRIPT_PARSED("next-free-honeycomb", [
    {"[[APP_NAME]]", App#app.name},
    {"[[SLOT_DIR]]", bh_md5:hex(UniqueName)},
    {"[[DESTINATION]]", BaseDir}
  ]),
  proplists:get_value(dir, Proplists).
  
handle_pid_exit(_Pid, _Reason, State) ->
  State.