-module(fb_signed_request).

-export([parse/2, generate/2, generate/3]).

%% Exported for tests
-export([decode_body/1]).

-define(PADDING, re:compile("(=|%3d)+$", [caseless])).
-define(SUPPORTED_ALGORITHMS, re:compile("\"algorithm\"\s*:\s*\"HMAC-SHA256\"")).


parse(Request, Secret) ->
    try
        [Signature, Payload] = extract_signature_and_payload(Request),
        Data                 = decode_body(Payload),
        validate_algorithm(Data),
        validate_signature(Signature, Payload, Secret),
        {ok, Data}
    catch
        {fb_signed_request, Message} -> {error, Message}
    end.


generate(Payload, Secret) ->
    EncodedPayload = url_safe(
        strip_padding(
            base64:encode_to_string(Payload)
        )
    ),

    EncodedSignature = create_signature(EncodedPayload, Secret),
    lists:flatten([EncodedSignature, ".", EncodedPayload]).


generate(Payload, Secret, [{return, binary}]) ->
    list_to_binary(generate(Payload, Secret)).


extract_signature_and_payload(Request) ->
    case re:split(Request, "\\.", [{return, list}]) of
        [Signature, Payload] -> [Signature, Payload];
        _                    -> throw({fb_signed_request, invalid_format})
    end.


decode_body(Payload) when is_binary(Payload) ->
    decode_body( binary_to_list(Payload) );


decode_body(Payload) when is_list(Payload) ->
    try
        list_to_binary(
            base64:decode_to_string(
                base64_pad( url_safe_decode( Payload ) ) )
        )
    catch
       _:_ -> throw({fb_signed_request, invalid_payload})
    end.


%% @doc does what it says
validate_algorithm(Data) ->
    {ok, Regex} = ?SUPPORTED_ALGORITHMS,
    try
        {match, _} = re:run(Data, Regex)
    catch
        error:{badmatch,_} -> throw({fb_signed_request, unsupported_algorithm})
    end.

%% @doc does what it says
validate_signature(Signature, Payload, Secret) ->
    try
        ComputedSignature = create_signature(Payload, Secret),
        ComputedSignature = Signature
    catch
        error:{badmatch,_} -> throw({fb_signed_request, invalid_signature})
    end.


%% @doc Calculate signature from Json and FB App Secret
create_signature( Payload, Secret ) ->
    strip_padding(
        url_safe(
            base64:encode_to_string(
                hmac:hmac256(Secret, Payload)
            )
        )
    ).


%% @doc Transforms the given signature into a URL-safe format.
url_safe( Signature ) ->
    lists:map(fun(Element) ->
        case Element of
            43 -> 45;
            47 -> 95;
            _  -> Element
        end
    end,
    Signature
  ).

%% @doc Transforms payload in URL-safe format into decodable format
url_safe_decode( Payload ) ->
    lists:map(fun(Element) ->
        case Element of
            45 -> 43;
            95 -> 47;
            _  -> Element
        end
    end,
    Payload
  ).

%% @doc Strip trailing '=' from base64 because that is how facebook rolls
strip_padding( Signature ) ->
    {ok, Regex} = ?PADDING,
    case re:replace(Signature, Regex, "", [global, {return, list}]) of
        [Result|[]] -> Result;
        Result      -> Result
    end.




%% @doc Add trailing '=' from base64 string
base64_pad( String ) ->
    Length = length(String),
    Remainder = Length rem 4,
    ToPad = case Remainder of
        0 -> 0;
        N -> 4 - N
    end,
    string:left(String, Length + ToPad, $=).
