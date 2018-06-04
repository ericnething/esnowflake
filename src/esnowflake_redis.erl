%%% @doc
%%% publish random uniq worker id
%%%
%%% @end
-module(esnowflake_redis).

-export([start_link/1, get_wid/0, setxx_wid/1, setnx_wid/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-behaviour(gen_server).

-include("esnowflake.hrl").

-define(KEY_PREFIX, esf).
-define(EXPIRE, 60).
-define(SERVER, ?MODULE).

-record(state, {
    redis = undefined :: undefined | inet:port(),
    range_ids = lists:seq(0, 1023),
    expire = ?EXPIRE :: non_neg_integer()
}).

start_link(C) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [C], []).

get_wid() ->
    gen_server:call(?SERVER, get_wid).

%% @doc
%% set with xx(only set key already exist) and expire
%% @end
-spec setxx_wid(Key :: integer()) -> {ok, binary()} | {ok, undefined} | {error, term()}.
setxx_wid(Wid) ->
    gen_server:call(?SERVER, {setxx, Wid, Wid}).

%% @doc
%% set with xx(only set key not exist) and expire.
%% @end
-spec setnx_wid(Wid :: integer()) -> {ok, binary()} | {ok, undefined} | {error, term()}.
setnx_wid(Wid) ->
    gen_server:call(?SERVER, {setnx, Wid, Wid}).

init([C]) ->
    EX = application:get_env(esnowflake, worker_id_expire, ?EXPIRE),
    {ok, #state{redis = C, expire = EX}}.

handle_cast(_Info, State) ->
    {noreply, State}.

handle_call(get_wid, _From, State = #state{redis = C, range_ids = RIds}) ->
    Pattern = lists:flatten(io_lib:format("~p:*", [?KEY_PREFIX])),
    {ok, Keys} = eredis:q(C, ["KEYS", Pattern]),
    {ok, UsedWids} = eredis:q(C, ["MGET", Keys]),
    case lists:subtract(RIds, UsedWids) of
        [] ->
            {reply, all_worker_ids_assigned, State};
        OKIds ->
            Wid = lists:nth(rand:uniform(length(OKIds)), OKIds),
            {reply, Wid, State}
    end;
handle_call({setnx, Key, Val}, _From, State = #state{redis = C}) ->
    EKey = lists:flatten(io_lib:format("~p:~p", [?KEY_PREFIX, Key])),
    Ret = eredis:q(C, ["SET", EKey, Val, "EX", ?EXPIRE, "NX"]),
    {reply, Ret, State};
handle_call({setxx, Key, Val}, _From, State = #state{redis = C}) ->
    EKey = lists:flatten(io_lib:format("~p:~p", [?KEY_PREFIX, Key])),
    Ret = eredis:q(C, ["SET", EKey, Val, "EX", ?EXPIRE, "XX"]),
    {reply, Ret, State};
handle_call(_Info, _From, State) ->
    {reply, ok, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
