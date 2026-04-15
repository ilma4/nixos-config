final: prev: {
  # FIXME: https://github.com/prometheus-community/smartctl_exporter/issues/305
  # https://github.com/prometheus-community/smartctl_exporter/issues/326
  prometheus-smartctl-exporter = prev.prometheus-smartctl-exporter.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        # Upstream issue: the pedantic registry turns changing SMART
        # descriptors into HTTP 500 responses on /metrics.
        substituteInPlace main.go \
          --replace-fail 'prometheus.NewPedanticRegistry()' 'prometheus.NewRegistry()'
      '';
  });
}
