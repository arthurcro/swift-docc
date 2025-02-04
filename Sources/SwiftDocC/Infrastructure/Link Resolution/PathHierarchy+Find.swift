/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension PathHierarchy {
    /// Attempts to find an element in the path hierarchy for a given path relative to another element.
    ///
    /// - Parameters:
    ///   - rawPath: The documentation link path string.
    ///   - parent: An optional identifier for the node in the hierarchy to search relative to.
    ///   - onlyFindSymbols: Whether or not only symbol matches should be found.
    /// - Returns: Returns the unique identifier for the found match or raises an error if no match can be found.
    /// - Throws: Raises a ``PathHierarchy/Error`` if no match can be found.
    func find(path rawPath: String, parent: ResolvedIdentifier? = nil, onlyFindSymbols: Bool) throws -> ResolvedIdentifier {
        let node = try findNode(path: rawPath, parentID: parent, onlyFindSymbols: onlyFindSymbols)
        if node.identifier == nil {
            throw Error.unfindableMatch(node)
        }
        if onlyFindSymbols, node.symbol == nil {
            throw Error.nonSymbolMatchForSymbolLink
        }
        return node.identifier
    }
    
    private func findNode(path rawPath: String, parentID: ResolvedIdentifier?, onlyFindSymbols: Bool) throws -> Node {
        // The search for a documentation element can be though of as 3 steps:
        // - First, parse the path into structured path components.
        // - Second, find nodes that match the beginning of the path as starting points for the search
        // - Third, traverse the hierarchy from those starting points to search for the node.
        let (path, isAbsolute) = Self.parse(path: rawPath)
        guard !path.isEmpty else {
            throw Error.notFound(remaining: [], availableChildren: [])
        }
        
        var remaining = path[...]
        
        // If the first path component is "tutorials" or "documentation" then use that information to narrow the search.
        let isKnownTutorialPath      = remaining.first!.full == NodeURLGenerator.Path.tutorialsFolderName
        let isKnownDocumentationPath = remaining.first!.full == NodeURLGenerator.Path.documentationFolderName
        if isKnownDocumentationPath || isKnownTutorialPath {
            // Skip this component since it isn't represented in the path hierarchy.
            remaining.removeFirst()
        }
        
        guard let firstComponent = remaining.first else {
            throw Error.notFound(remaining: [], availableChildren: [])
        }
        
        // A function to avoid eagerly computing the full path unless it needs to be presented in an error message.
        func parsedPathForError() -> [PathComponent] {
            Self.parse(path: rawPath, omittingEmptyComponents: false).components
        }
        
        if !onlyFindSymbols {
            // If non-symbol matches are possible there is a fixed order to try resolving the link:
            // Articles match before tutorials which match before the tutorial overview page which match before symbols.
            
            // Non-symbols have a very shallow hierarchy so the simplified search peak at the first few layers and then searches only one subtree once if finds a probable match.
            lookForArticleRoot: if !isKnownTutorialPath {
                if articlesContainer.matches(firstComponent) {
                    if let next = remaining.dropFirst().first {
                        if !articlesContainer.anyChildMatches(next) {
                            break lookForArticleRoot
                        }
                    }
                    return try searchForNode(descendingFrom: articlesContainer, pathComponents: remaining.dropFirst(), parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                } else if articlesContainer.anyChildMatches(firstComponent) {
                    return try searchForNode(descendingFrom: articlesContainer, pathComponents: remaining, parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                }
            }
            if !isKnownDocumentationPath {
                if tutorialContainer.matches(firstComponent) {
                    return try searchForNode(descendingFrom: tutorialContainer, pathComponents: remaining.dropFirst(), parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                } else if tutorialContainer.anyChildMatches(firstComponent)  {
                    return try searchForNode(descendingFrom: tutorialContainer, pathComponents: remaining, parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                }
                // The parent for tutorial overviews / technologies is "tutorials" which has already been removed above, so no need to check against that name.
                else if tutorialOverviewContainer.anyChildMatches(firstComponent)  {
                    return try searchForNode(descendingFrom: tutorialOverviewContainer, pathComponents: remaining, parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                }
            }
        }
        
        // A function to avoid repeating the
        func searchForNodeInModules() throws -> Node {
            // Note: This captures `parentID`, `remaining`, and `parsedPathForError`.
            if let moduleMatch = modules[firstComponent.full] ?? modules[firstComponent.name] {
                return try searchForNode(descendingFrom: moduleMatch, pathComponents: remaining.dropFirst(), parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
            }
            if modules.count == 1 {
                do {
                    return try searchForNode(descendingFrom: modules.first!.value, pathComponents: remaining, parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                } catch {
                    // Ignore this error and raise an error about not finding the module instead.
                }
            }
            let topLevelNames = Set(modules.keys + [articlesContainer.name, tutorialContainer.name])
            throw Error.notFound(remaining: Array(remaining), availableChildren: topLevelNames)
        }
        
        // A recursive function to traverse up the path hierarchy searching for the matching node
        func searchForNodeUpTheHierarchy(from startingPoint: Node?, path: ArraySlice<PathComponent>) throws -> Node {
            guard let possibleStartingPoint = startingPoint else {
                // If the search has reached the top of the hierarchy, check the modules as a base case to break the recursion.
                do {
                    return try searchForNodeInModules()
                } catch {
                    // If the node couldn't be found in the modules, search the non-matching parent to achieve a more specific error message
                    if let parentID = parentID {
                        return try searchForNode(descendingFrom: lookup[parentID]!, pathComponents: path, parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                    }
                    throw error
                }
            }
            
            // If the path isn't empty we would have already found a node.
            let firstComponent = path.first!
            
            // Keep track of the inner most error and raise that if no node is found.
            var innerMostError: Swift.Error?
            
            // If the starting point's children match this component, descend the path hierarchy from there.
            if possibleStartingPoint.anyChildMatches(firstComponent) {
                do {
                    return try searchForNode(descendingFrom: possibleStartingPoint, pathComponents: path, parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                } catch {
                    innerMostError = error
                }
            }
            // It's possible that the component is ambiguous at the parent. Checking if this node matches the first component avoids that ambiguity.
            if possibleStartingPoint.matches(firstComponent) {
                do {
                    return try searchForNode(descendingFrom: possibleStartingPoint, pathComponents: path.dropFirst(), parsedPathForError: parsedPathForError, onlyFindSymbols: onlyFindSymbols)
                } catch {
                    if innerMostError == nil {
                        innerMostError = error
                    }
                }
            }
            
            do {
                return try searchForNodeUpTheHierarchy(from: possibleStartingPoint.parent, path: path)
            } catch {
                throw innerMostError ?? error
            }
        }
        
        if !isAbsolute, let parentID = parentID {
            // If this is a relative link with a known starting point, search from that node up the hierarchy.
            return try searchForNodeUpTheHierarchy(from: lookup[parentID]!, path: remaining)
        }
        return try searchForNodeInModules()
    }
    
    private func searchForNode(
        descendingFrom startingPoint: Node,
        pathComponents: ArraySlice<PathComponent>,
        parsedPathForError: () -> [PathComponent],
        onlyFindSymbols: Bool
    ) throws -> Node {
        var node = startingPoint
        var remaining = pathComponents[...]
        
        // Third, search for the match relative to the start node.
        if remaining.isEmpty {
            // If all path components were consumed, then the start of the search is the match.
            return node
        }
        
        // Search for the remaining components from the node
        while true {
            let (children, pathComponent) = try findChildTree(node: &node, parsedPath: parsedPathForError(), remaining: remaining)
            
            do {
                guard let child = try children.find(pathComponent.kind, pathComponent.hash) else {
                    // The search has ended with a node that doesn't have a child matching the next path component.
                    throw makePartialResultError(node: node, parsedPath: parsedPathForError(), remaining: remaining)
                }
                node = child
                remaining = remaining.dropFirst()
                if remaining.isEmpty {
                    // If all path components are consumed, then the match is found.
                    return child
                }
            } catch DisambiguationContainer.Error.lookupCollision(let collisions) {
                func handleWrappedCollision() throws -> Node {
                    try handleCollision(node: node, parsedPath: parsedPathForError, remaining: remaining, collisions: collisions, onlyFindSymbols: onlyFindSymbols)
                }
                
                // See if the collision can be resolved by looking ahead on level deeper.
                guard let nextPathComponent = remaining.dropFirst().first else {
                    // This was the last path component so there's nothing to look ahead.
                    //
                    // It's possible for a symbol that exist on multiple languages to collide with itself.
                    // Check if the collision can be resolved by finding a unique symbol or an otherwise preferred match.
                    var uniqueCollisions: [String: Node] = [:]
                    for (node, _) in collisions {
                        guard let symbol = node.symbol else {
                            // Non-symbol collisions should have already been resolved
                            return try handleWrappedCollision()
                        }
                        
                        let id = symbol.identifier.precise
                        if symbol.identifier.interfaceLanguage == "swift" || !uniqueCollisions.keys.contains(id) {
                            uniqueCollisions[id] = node
                        }
                        
                        guard uniqueCollisions.count < 2 else {
                            // Encountered more than one unique symbol
                            return try handleWrappedCollision()
                        }
                    }
                    // A wrapped error would have been raised while iterating over the collection.
                    return uniqueCollisions.first!.value
                }
                // Try resolving the rest of the path for each collision ...
                let possibleMatches = collisions.compactMap {
                    return try? $0.node.children[nextPathComponent.name]?.find(nextPathComponent.kind, nextPathComponent.hash)
                }
                // If only one collision matches, return that match.
                if possibleMatches.count == 1 {
                    return possibleMatches.first!
                }
                // If all matches are the same symbol, return the Swift version of that symbol
                if !possibleMatches.isEmpty, possibleMatches.dropFirst().allSatisfy({ $0.symbol?.identifier.precise == possibleMatches.first!.symbol?.identifier.precise }) {
                    return possibleMatches.first(where: { $0.symbol?.identifier.interfaceLanguage == "swift" }) ?? possibleMatches.first!
                }
                // Couldn't resolve the collision by look ahead.
                return try handleCollision(node: node, parsedPath: parsedPathForError, remaining: remaining, collisions: collisions, onlyFindSymbols: onlyFindSymbols)
            }
        }
    }
                        
    private func handleCollision(
        node: Node,
        parsedPath: () -> [PathComponent],
        remaining: ArraySlice<PathComponent>,
        collisions: [(node: PathHierarchy.Node, disambiguation: String)],
        onlyFindSymbols: Bool
    ) throws -> Node {
        if let favoredMatch = collisions.singleMatch({ $0.node.isDisfavoredInCollision == false }) {
            return favoredMatch.node
        }
        // If a module has the same name as the article root (which is named after the bundle display name) then its possible
        // for an article a symbol to collide. Articles aren't supported in symbol links but symbols are supported in general
        // documentation links (although the non-symbol result is prioritized).
        //
        // There is a later check that the returned node is a symbol for symbol links, but that won't happen if the link is a
        // collision. To fully handle the collision in both directions, the check below uses `onlyFindSymbols` in the closure
        // so that only symbol matches are returned for symbol links (when `onlyFindSymbols` is `true`) and non-symbol matches
        // for general documentation links (when `onlyFindSymbols` is `false`).
        //
        // It's a more compact way to write
        //
        //     if onlyFindSymbols {
        //        return $0.node.symbol != nil
        //     } else {
        //        return $0.node.symbol == nil
        //     }
        if let symbolOrNonSymbolMatch = collisions.singleMatch({ ($0.node.symbol != nil) == onlyFindSymbols }) {
            return symbolOrNonSymbolMatch.node
        }
        
        throw Error.lookupCollision(
            partialResult: (
                node,
                Array(parsedPath().dropLast(remaining.count))
            ),
            remaining: Array(remaining),
            collisions: collisions.map { ($0.node, $0.disambiguation) }
        )
    }
    
    private func makePartialResultError(
        node: Node,
        parsedPath: [PathComponent],
        remaining: ArraySlice<PathComponent>
    ) -> Error {
        if let disambiguationTree = node.children[remaining.first!.name] {
            return Error.unknownDisambiguation(
                partialResult: (
                    node,
                    Array(parsedPath.dropLast(remaining.count))
                ),
                remaining: Array(remaining),
                candidates: disambiguationTree.disambiguatedValues().map {
                    (node: $0.value, disambiguation: String($0.disambiguation.makeSuffix().dropFirst()))
                }
            )
        }
        
        return Error.unknownName(
            partialResult: (
                node,
                Array(parsedPath.dropLast(remaining.count))
            ),
            remaining: Array(remaining),
            availableChildren: Set(node.children.keys)
        )
    }
    
    /// Finds the child disambiguation tree for a given node that match the remaining path components.
    /// - Parameters:
    ///   - node: The current node.
    ///   - remaining: The remaining path components.
    /// - Returns: The child disambiguation tree and path component.
    private func findChildTree(node: inout Node, parsedPath: @autoclosure () -> [PathComponent], remaining: ArraySlice<PathComponent>) throws -> (DisambiguationContainer, PathComponent) {
        var pathComponent = remaining.first!
        if let match = node.children[pathComponent.full] {
            // The path component parsing may treat dash separated words as disambiguation information.
            // If the parsed name didn't match, also try the original.
            pathComponent.kind = nil
            pathComponent.hash = nil
            return (match, pathComponent)
        } else if let match = node.children[pathComponent.name] {
            return (match, pathComponent)
        }
        // The search has ended with a node that doesn't have a child matching the next path component.
        throw makePartialResultError(node: node, parsedPath: parsedPath(), remaining: remaining)
    }
}

// MARK: Disambiguation Container

extension PathHierarchy.DisambiguationContainer {
    /// Errors finding values in the disambiguation tree
    enum Error: Swift.Error {
        /// Multiple matches found.
        ///
        /// Includes a list of values paired with their missing disambiguation suffixes.
        case lookupCollision([(node: PathHierarchy.Node, disambiguation: String)])
    }
    
    /// Attempts to find a value in the disambiguation tree based on partial disambiguation information.
    ///
    /// There are 3 possible results:
    ///  - No match is found; indicated by a `nil` return value.
    ///  - Exactly one match is found; indicated by a non-nil return value.
    ///  - More than one match is found; indicated by a raised error listing the matches and their missing disambiguation.
    func find(_ kind: String?, _ hash: String?) throws -> PathHierarchy.Node? {
        if let kind = kind {
            // Need to match the provided kind
            guard let subtree = storage[kind] else { return nil }
            if let hash = hash {
                return subtree[hash]
            } else if subtree.count == 1 {
                return subtree.values.first
            } else {
                // Subtree contains more than one match.
                throw Error.lookupCollision(subtree.map { ($0.value, $0.key) })
            }
        } else if storage.count == 1, let subtree = storage.values.first {
            // Tree only contains one kind subtree
            if let hash = hash {
                return subtree[hash]
            } else if subtree.count == 1 {
                return subtree.values.first
            } else {
                // Subtree contains more than one match.
                throw Error.lookupCollision(subtree.map { ($0.value, $0.key) })
            }
        } else if let hash = hash {
            // Need to match the provided hash
            let kinds = storage.filter { $0.value.keys.contains(hash) }
            if kinds.isEmpty {
                return nil
            } else if kinds.count == 1 {
                return kinds.first!.value[hash]
            } else {
                // Subtree contains more than one match
                throw Error.lookupCollision(kinds.map { ($0.value[hash]!, $0.key) })
            }
        }
        // Disambiguate by a mix of kinds and USRs
        throw Error.lookupCollision(self.disambiguatedValues().map { ($0.value, $0.disambiguation.value()) })
    }
}

// MARK: Private helper extensions

private extension Sequence {
    /// Returns the only element of the sequence that satisfies the given predicate.
    /// - Parameters:
    ///   - predicate: A closure that takes an element of the sequence as its argument and returns a Boolean value indicating whether the element is a match.
    /// - Returns: The only element of the sequence that satisfies `predicate`, or `nil` if  multiple elements satisfy the predicate or if no element satisfy the predicate.
    /// - Complexity: O(_n_), where _n_ is the length of the sequence.
    func singleMatch(_ predicate: (Element) -> Bool) -> Element? {
        var match: Element?
        for element in self where predicate(element) {
            guard match == nil else {
                // Found a second match. No need to check the rest of the sequence.
                return nil
            }
            match = element
        }
        return match
    }
}

private extension PathHierarchy.Node {
    func matches(_ component: PathHierarchy.PathComponent) -> Bool {
        if let symbol = symbol {
            return name == component.name
            && (component.kind == nil || component.kind == symbol.kind.identifier.identifier)
            && (component.hash == nil || component.hash == symbol.identifier.precise.stableHashString)
        } else {
            return name == component.full
        }
    }
    
    func anyChildMatches(_ component: PathHierarchy.PathComponent) -> Bool {
        let keys = children.keys
        return keys.contains(component.name) || keys.contains(component.full)
    }
}
