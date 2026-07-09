// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-2012 The Bitcoin developers
// Distributed under the MIT/X11 software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <cstdio>

#include "util.h"
#include "bitcoinrpc.h"

//
// 2GiveCoin RPC client. Parses command-line parameters and the configuration
// file (so -rpcuser/-rpcpassword are available) then forwards the request to
// the running 2GiveCoind daemon via the JSON-RPC client in bitcoinrpc.cpp.
//
int main(int argc, char *argv[])
{
#ifdef _MSC_VER
    _CrtSetReportMode(_CRT_WARN, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_WARN, CreateFileA("NUL", GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, 0));
#endif
    setbuf(stdin, NULL);
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    // Parse [options] and read rpcuser/rpcpassword from the config file.
    ParseParameters(argc, argv);
    ReadConfigFile(mapArgs, mapMultiArgs);

    if (mapArgs.count("-?") || mapArgs.count("--help"))
    {
        std::string strUsage =
            "2GiveCoin-cli version " + FormatFullVersion() + "\n\n" +
            _("Usage:") + "\n" +
            "  2GiveCoin-cli [options] <command> [params]   " + _("Send command to 2GiveCoind") + "\n" +
            "  2GiveCoin-cli [options] help                 " + _("List commands") + "\n" +
            "  2GiveCoin-cli [options] help <command>       " + _("Get help for a command") + "\n\n" +
            _("Options:") + "\n" +
            "  -?                     " + _("This help message") + "\n" +
            "  -conf=<file>           " + _("Specify configuration file (default: 2GiveCoin.conf)") + "\n" +
            "  -datadir=<dir>         " + _("Specify data directory") + "\n" +
            "  -rpcuser=<user>        " + _("Username for RPC basic auth") + "\n" +
            "  -rpcpassword=<pw>      " + _("Password for RPC basic auth") + "\n" +
            "  -rpcconnect=<ip>       " + _("Send commands to node running on <ip> (default: 127.0.0.1)") + "\n" +
            "  -rpcport=<port>        " + _("Connect to RPC port (default: 53590 or 43590 for testnet)") + "\n" +
            "  -rpcssl                " + _("Use HTTPS for RPC connection") + "\n";
        fprintf(stdout, "%s", strUsage.c_str());
        return 0;
    }

    return CommandLineRPC(argc, argv);
}
