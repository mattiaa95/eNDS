//
//  Constants.swift
//  eNDS
//
//  Shared constants for the Settings module.
//
//  These used to point at iGBA's WordPress site, on a "one support hub for the
//  family of apps" rationale. That does not survive App Review: the privacy
//  policy a reviewer opens has to describe *this* app, and eNDS's profile is
//  genuinely different — it asks for the microphone, and it has no ads and no
//  tracking at all, none of which iGBA's policy says.
//
//  eNDS now has its own pages, served from a static site with no analytics and
//  no third-party requests (source: the eNDS-site folder alongside this repo).
//

import Foundation

enum INDSConstants {
    /// The landing page's contact section, so "Support" lands on the email
    /// button rather than making the user hunt for it.
    static let supportURL = URL(string: "https://mattiaa95.github.io/#contact")!
    static let privacyPolicyURL = URL(string: "https://igbaapp.wordpress.com/privacy-policy/")!
    static let termsURL = URL(string: "https://igbaapp.wordpress.com/terms-conditions/")!
    static let sourceCodeURL = URL(string: "https://github.com/mattiaa95/eNDS")!
    static let melonDSURL = URL(string: "https://github.com/melonDS-emu/melonDS")!
}
