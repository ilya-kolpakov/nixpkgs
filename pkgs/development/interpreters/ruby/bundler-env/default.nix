{ stdenv, runCommand, writeText, writeScript, writeScriptBin, ruby, lib
, callPackage, defaultGemConfig, fetchurl, fetchgit, buildRubyGem, buildEnv
, rubygems
, git
, makeWrapper
, bundler
, tree
}@defs:

{ name, gemset, gemfile, lockfile, ruby ? defs.ruby, gemConfig ? defaultGemConfig
, postBuild ? null
, document ? []
, meta ? {}
, ignoreCollisions ? false
, ...
}@args:

let

  shellEscape = x: "'${lib.replaceChars ["'"] [("'\\'" + "'")] x}'";
  importedGemset = import gemset;
  applyGemConfigs = attrs:
    (if gemConfig ? "${attrs.gemName}"
    then attrs // gemConfig."${attrs.gemName}" attrs
    else attrs);
  configuredGemset = lib.flip lib.mapAttrs importedGemset (name: attrs:
    applyGemConfigs (attrs // { gemName = name; })
  );
  hasBundler = builtins.hasAttr "bundler" importedGemset;
  bundler = if hasBundler then gems.bundler else defs.bundler.override (attrs: { inherit ruby; });
  rubygems = defs.rubygems.override (attrs: { inherit ruby; });
  gems = lib.flip lib.mapAttrs configuredGemset (name: attrs:
    buildRubyGem ((removeAttrs attrs ["source"]) // attrs.source // {
      inherit ruby rubygems;
      gemName = name;
      gemPath = map (gemName: gems."${gemName}") (attrs.dependencies or []);
    }));
  # We have to normalize the Gemfile.lock, otherwise bundler tries to be
  # helpful by doing so at run time, causing executables to immediately bail
  # out. Yes, I'm serious.
  confFiles = runCommand "gemfile-and-lockfile" {} ''
    mkdir -p $out
    cp ${gemfile} $out/Gemfile
    cp ${lockfile} $out/Gemfile.lock

    cd $out
    chmod +w Gemfile.lock
    source ${rubygems}/nix-support/setup-hook
    export GEM_PATH=${bundler}/${ruby.gemPath}
    ${ruby}/bin/ruby -rubygems -e \
      "require 'bundler'; Bundler.definition.lock('Gemfile.lock')"
  '';
  envPaths = lib.attrValues gems ++ lib.optional (!hasBundler) bundler;
  bundlerEnv = buildEnv {
    inherit name ignoreCollisions;
    paths = envPaths;
    pathsToLink = [ "/lib" ];
    postBuild = ''
      source ${rubygems}/nix-support/setup-hook

      ${ruby}/bin/ruby ${./gen-bin-stubs.rb} \
        "${ruby}/bin/ruby" \
        "${confFiles}/Gemfile" \
        "$out/${ruby.gemPath}" \
        "${bundler}/${ruby.gemPath}" \
        ${shellEscape (toString envPaths)}
    '' + lib.optionalString (postBuild != null) postBuild;
    passthru = {
      inherit ruby bundler meta gems;
      env = let
        irbrc = builtins.toFile "irbrc" ''
          if !(ENV["OLD_IRBRC"].nil? || ENV["OLD_IRBRC"].empty?)
            require ENV["OLD_IRBRC"]
          end
          require 'rubygems'
          require 'bundler/setup'
        '';
        in stdenv.mkDerivation {
          name = "interactive-${name}-environment";
          nativeBuildInputs = [ ruby bundlerEnv ];
          shellHook = ''
            export BUNDLE_GEMFILE=${confFiles}/Gemfile
            export BUNDLE_PATH=${bundlerEnv}/${ruby.gemPath}
            export GEM_HOME=${bundlerEnv}/${ruby.gemPath}
            export GEM_PATH=${bundlerEnv}/${ruby.gemPath}
            export OLD_IRBRC="$IRBRC"
            export IRBRC=${irbrc}
          '';
          buildCommand = ''
            echo >&2 ""
            echo >&2 "*** Ruby 'env' attributes are intended for interactive nix-shell sessions, not for building! ***"
            echo >&2 ""
            exit 1
          '';
        };
    };
  };

in

bundlerEnv
