function FindProxyForURL(url, host) {
  host = host.toLowerCase();

  if (
    host === "linux.do" ||
    dnsDomainIs(host, ".linux.do") ||
    host === "idcflare.com" ||
    dnsDomainIs(host, ".idcflare.com")
  ) {
    return "PROXY 127.0.0.1:18080";
  }

  return "DIRECT";
}
