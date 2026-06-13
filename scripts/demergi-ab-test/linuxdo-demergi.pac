function FindProxyForURL(url, host) {
  host = host.toLowerCase();

  if (
    isPlainHostName(host) ||
    host === "localhost" ||
    shExpMatch(host, "127.*") ||
    shExpMatch(host, "10.*") ||
    shExpMatch(host, "172.16.*") ||
    shExpMatch(host, "172.17.*") ||
    shExpMatch(host, "172.18.*") ||
    shExpMatch(host, "172.19.*") ||
    shExpMatch(host, "172.20.*") ||
    shExpMatch(host, "172.21.*") ||
    shExpMatch(host, "172.22.*") ||
    shExpMatch(host, "172.23.*") ||
    shExpMatch(host, "172.24.*") ||
    shExpMatch(host, "172.25.*") ||
    shExpMatch(host, "172.26.*") ||
    shExpMatch(host, "172.27.*") ||
    shExpMatch(host, "172.28.*") ||
    shExpMatch(host, "172.29.*") ||
    shExpMatch(host, "172.30.*") ||
    shExpMatch(host, "172.31.*") ||
    shExpMatch(host, "192.168.*") ||
    shExpMatch(host, "169.254.*")
  ) {
    return "DIRECT";
  }

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
