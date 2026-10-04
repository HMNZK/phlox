import Foundation

/// 共有走査で扱える違いは、言語別のデータとして保持する。
struct ChatSyntaxRules: Sendable {
    static let shared: [ChatCodeLanguage: ChatSyntaxRules] = Dictionary(uniqueKeysWithValues:
        ChatCodeLanguage.allCases.map { ($0, ChatSyntaxRules($0)) }
    )

    var keywords: Set<String> = []
    var lineComments: [String] = []
    var blocks: [(String, String)] = []
    var quotes: [UInt8] = [34, 39]
    var triple = false
    var insensitive = false
    var hasVariables = false
    var hasAnnotations = false
    var hasAssignmentKeys = false
    var usesLineRules = false
    var nestedComments = false
    var quoteNeedsBoundary = false
    var lineCommentNeedsBoundary = false
    var identifierApostrophes = false
    var identifierHyphens = false
    var doubledSingleQuotes = false
    var escapeByte: UInt8? = 92
    var rawBackticks = false

    static let subcommands: Set<String> = ["add", "branch", "checkout", "clone", "commit", "diff", "log", "push", "status", "test"]

    init(_ language: ChatCodeLanguage) {
        func words(_ text: String) { keywords = Set(text.split(separator: " ").map(String.init)) }
        switch language {
        case .swift:
            words("actor as associatedtype async await break case catch class continue default defer deinit do else enum extension false fileprivate for func guard if import in init inout internal is let nil nonisolated open operator private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var where while")
        case .c, .objectiveC:
            words("auto bool break case catch char class const constexpr continue default delete do double else enum explicit extern false float for friend goto if inline int long namespace new nullptr operator private protected public register return short signed sizeof static struct super switch template this throw true try typedef typename union unsigned using virtual void volatile while id interface implementation end property synthesize dynamic selector protocol autoreleasepool import include define ifdef ifndef endif")
        case .java:
            words("abstract assert boolean break byte case catch char class const continue default do double else enum extends false final finally float for if implements import instanceof int interface long native new null package private protected public record return short static strictfp super switch synchronized this throw throws transient true try var void volatile while yield")
        case .kotlin:
            words("as break by catch class companion const continue constructor data do else enum false finally for fun if import in interface internal is null object open operator override package private protected public return sealed super suspend this throw true try typealias val var when while")
        case .csharp:
            words("abstract as async await base bool break case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly record ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while yield")
        case .go:
            words("break case chan const continue default defer else fallthrough false for func go goto if import interface map nil package range return select struct switch true type var")
        case .rust:
            words("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while")
        case .python:
            words("and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return self True try while with yield")
        case .ruby:
            words("alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return require self super then true undef unless until when while yield")
        case .php:
            words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty endfor endforeach endif endwhile eval exit extends false final finally fn for foreach function global if implements include instanceof interface isset list namespace new null or print private protected public require return static switch throw trait true try unset use var while xor yield")
        case .perl:
            words("my our local sub use package require if elsif else unless while until for foreach continue last next redo goto return undef defined die print say given when state")
        case .lua:
            words("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")
        case .r:
            words("if else repeat while function for in next break TRUE FALSE NULL Inf NaN NA library require")
        case .dart:
            words("abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null on operator part required rethrow return set show static super switch sync this throw true try typedef var void while with yield")
        case .scala:
            words("abstract case catch class def do else enum export extends false final finally for given if implicit import lazy match new null object override package private protected return sealed super then this throw trait true try type val var while with yield")
        case .elixir:
            words("after alias and case catch cond def defmodule defp do else end false fn for if import in nil not or quote raise receive require rescue true try unless unquote use when with")
        case .haskell, .literateHaskell:
            words("case class data default deriving do else foreign if import in infix infixl infixr instance let module newtype of then type where")
        case .javascript, .typescript, .jsx, .tsx:
            words("abstract as async await break case catch class const continue debugger declare default delete do else enum export extends false finally for from function if implements import in instanceof interface keyof let namespace new null of private protected public readonly return satisfies static super switch this throw true try type typeof undefined var void while yield")
            if language == .typescript || language == .tsx { keywords.formUnion(["any", "boolean", "never", "number", "string", "symbol", "unknown", "bigint", "object"]) }
        case .shell:
            words("if then else elif fi for while until do done case esac in function select time coproc")
        case .fish:
            words("if else end for while switch case function begin and or not set in break continue return")
        case .powershell:
            words("begin break catch class continue data do dynamicparam else elseif end enum exit filter finally for foreach from function if in param process return switch throw trap try until using while workflow")
            insensitive = true
        case .sql:
            words("select from where insert into update delete create table drop alter and or not null join left right inner outer on group by order limit values set as distinct having union index primary key references default is in like case when then else end true false")
            insensitive = true
        case .graphql: words("query mutation subscription fragment on schema type input enum interface union scalar extend directive true false null")
        case .json, .jsonc, .json5: words("true false null")
        case .yaml, .toml: words("true false null yes no on off True False None")
        case .dockerfile:
            words("from run cmd label expose env add copy entrypoint volume user workdir arg onbuild stopsignal healthcheck shell")
            insensitive = true
        case .cmake:
            words("cmake_minimum_required project set option add_executable add_library target_link_libraries target_include_directories find_package include if else elseif endif foreach endforeach function endfunction macro endmacro")
            insensitive = true
        case .protobuf: words("syntax import package option message enum service rpc returns repeated optional required oneof map reserved extensions extend bool bytes double fixed32 fixed64 float int32 int64 sfixed32 sfixed64 sint32 sint64 string uint32 uint64 true false")
        case .hcl: words("true false null for in if resource data variable output locals module provider terraform dynamic")
        case .nix: words("assert else if in inherit let or rec then with true false null")
        default: break
        }
        switch language {
        case .python, .ruby, .perl, .r, .elixir, .shell, .fish, .powershell, .yaml, .toml, .ini,
             .env, .properties, .dockerfile, .makefile, .cmake, .ignore, .attributes, .nix, .hcl:
            lineComments = ["#"]
        case .lua, .haskell, .literateHaskell, .sql: lineComments = ["--"]
        case .latex, .bibtex: lineComments = ["%"]
        case .json, .plain, .log, .css: break
        default: lineComments = ["//"]
        }
        switch language {
        case .swift, .objectiveC, .c, .java, .kotlin, .csharp, .go, .rust, .php, .dart, .scala,
             .javascript, .typescript, .jsx, .tsx, .sql, .jsonc, .json5, .css, .scss, .less,
             .protobuf, .hcl, .nix: blocks = [("/*", "*/")]
        case .powershell: blocks = [("<#", "#>")]
        case .haskell, .literateHaskell: blocks = [("{-", "-}")]
        default: break
        }
        if language == .ini { lineComments.append(";") }
        if language == .graphql { lineComments = ["#"] }
        if [.swift, .json, .jsonc, .log, .latex, .bibtex].contains(language) { quotes = [34] }
        if language == .go || [.javascript, .typescript, .jsx, .tsx].contains(language) { quotes.append(96) }
        triple = [.swift, .python, .java, .kotlin, .csharp, .dart, .scala, .elixir, .graphql, .toml].contains(language)
        hasVariables = [.shell, .fish, .powershell, .php, .perl, .graphql, .env, .makefile, .cmake, .scss].contains(language)
        hasAnnotations = [.objectiveC, .java, .kotlin, .csharp, .dart, .scala, .css, .scss, .less, .bibtex].contains(language)
        hasAssignmentKeys = [.toml, .ini, .env, .properties, .hcl, .nix, .bibtex].contains(language)
        usesLineRules = [.log, .ini, .toml, .env, .properties, .ignore, .attributes, .literateHaskell,
                         .makefile, .dockerfile, .yaml, .c, .objectiveC, .csharp].contains(language)
        nestedComments = [.swift, .rust, .haskell, .literateHaskell, .kotlin].contains(language)
        quoteNeedsBoundary = language == .yaml
        identifierHyphens = language == .yaml
        lineCommentNeedsBoundary = [.yaml, .shell, .fish].contains(language)
        identifierApostrophes = language == .haskell || language == .literateHaskell
        doubledSingleQuotes = language == .yaml || language == .sql || language == .powershell
        if language == .powershell { escapeByte = 96 }
        rawBackticks = language == .go
    }
}
