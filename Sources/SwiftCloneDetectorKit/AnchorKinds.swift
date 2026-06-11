//
//  AnchorKinds.swift
//  SwiftCloneDetectorKit
//
//  Subtree roots significant enough to report as clones. Anchoring on these
//  boundaries — rather than every node — keeps the detector from matching
//  incidental fragments like bare member-access chains or argument lists.
//

import SwiftSyntax

let anchorKinds: Set<SyntaxKind> = [
    .codeBlockItem,
    .memberBlockItem,
    .functionDecl,
    .initializerDecl,
    .subscriptDecl,
    .accessorDecl,
    .variableDecl,
    .closureExpr,
    .ifExpr,
    .guardStmt,
    .forStmt,
    .whileStmt,
    .switchExpr,
    .switchCase
]
