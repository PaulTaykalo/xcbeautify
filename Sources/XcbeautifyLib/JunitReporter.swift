// Information about the JUNIT Schema/specification used in this file can be found here:
// * https://stackoverflow.com/a/9410271
// * https://github.com/bazelbuild/bazel/blob/45092bb122b840e3410845522df9fe89c59db465/src/java_tools/junitrunner/java/com/google/testing/junit/runner/model/AntXmlResultWriter.java#L29
// * http://windyroad.com.au/dl/Open%20Source/JUnit.xsd

import Foundation
import XMLCoder

public final class JunitReporter {
    private var components: [JunitComponent] = []
    
    public init() { }

    public func add(line: String) {
        switch line {
            case Matcher.failingTestMatcher:
                components.append(.failingTest(line))
            case Matcher.testCasePassedMatcher:
                components.append(.testCasePassed(line))
        case Matcher.testSuiteStartMatcher:
                components.append(.testSuiteStart(line))
            default:
                // Not needed for generating a junit report
                break
        }
    }
    
    public func generateReport() throws -> Data {
        let parser = JunitComponentParser()
        components.forEach { parser.parse(component: $0) }
        let encoder = XMLEncoder()
        encoder.keyEncodingStrategy = .lowercased
        encoder.outputFormatting = [.prettyPrinted]
        let result = parser.result()
        return try encoder.encode(result)
    }
}

private final class JunitComponentParser {
    private var mainTestSuiteName: String?
    private var testCases: [Testcase] = []

    func parse(component: JunitComponent) {
        switch component {
        case let .testSuiteStart(line):
            guard mainTestSuiteName == nil else {
                break
            }
            let groups = line.capturedGroups(with: .testSuiteStart)
            mainTestSuiteName = groups[0]

        case let .failingTest(line):
            let groups = line.capturedGroups(with: .failingTest)
            let testCase = Testcase(
                classname: groups[1],
                name: groups[2],
                time: nil,
                failure: .init(message: "\(groups[0]) - \(groups[3])")
            )
            testCases.append(testCase)

        case let .testCasePassed(line):
            let groups = line.capturedGroups(with: .testCasePassed)
            let testCase = Testcase(classname: groups[0], name: groups[1], time: groups[2], failure: nil)
            testCases.append(testCase)
        }
    }

    func result() -> Testsuites {
        var testSuites: [Testsuite] = []
        for testCase in testCases {
            let index: Int
            if let existingTestSuiteIndex = testSuites.firstIndex(where: { $0.name == testCase.classname }) {
                index = existingTestSuiteIndex
            } else {
                let newTestSuite = Testsuite(name: testCase.classname, testcases: [])
                testSuites.append(newTestSuite)
                index = testSuites.count - 1
            }
            var testSuite = testSuites[index]
            testSuite.testcases.append(testCase)
            testSuites[index] = testSuite
        }
        let container = Testsuites(name: mainTestSuiteName, testsuites: testSuites)
        return container
    }
}

private enum JunitComponent: Equatable {
    case testSuiteStart(String)
    case failingTest(String)
    case testCasePassed(String)
}

private struct Testsuites: Encodable, DynamicNodeEncoding {
    var name: String?
    var testsuites: [Testsuite] = []
    
    enum CodingKeys: String, CodingKey {
        case name
        case tests
        case failures
        case testsuites = "testsuite"
    }

    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        let key = CodingKeys(stringValue: key.stringValue)!
        switch key {
        case .name, .tests, .failures:
            return .attribute
        
        case .testsuites:
            return .element
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(testsuites.reduce(into: 0, { $0 += $1.testcases.count }), forKey: .tests)
        try container.encode(testsuites.reduce(into: 0, { $0 += $1.testcases.filter { $0.failure != nil }.count }), forKey: .failures)
        try container.encode(testsuites, forKey: .testsuites)
    }
}

private struct Testsuite: Encodable, DynamicNodeEncoding {
    let name: String
    var testcases: [Testcase]

    enum CodingKeys: String, CodingKey {
        case name
        case tests
        case failures
        case testcases = "testcase"
    }

    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        let key = CodingKeys(stringValue: key.stringValue)!
        switch key {
        case .name, .tests, .failures:
            return .attribute
        
        case .testcases:
            return .element
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(testcases.count, forKey: .tests)
        try container.encode(testcases.filter { $0.failure != nil }.count, forKey: .failures)
        try container.encode(testcases, forKey: .testcases)
    }
}

private struct Testcase: Codable, DynamicNodeEncoding {
    let classname: String
    let name: String
    let time: String?
    let failure: Failure?
    
    static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
        let key = CodingKeys(stringValue: key.stringValue)!
        switch key {
        case .classname, .name, .time:
            return .attribute
            
        case .failure:
            return .element
        }
    }
}

private extension Testcase {
    struct Failure: Codable, DynamicNodeEncoding {
        let message: String
        
        static func nodeEncoding(for key: CodingKey) -> XMLEncoder.NodeEncoding {
            let key = CodingKeys(stringValue: key.stringValue)!
            switch key {
            case .message:
                return .attribute
            }
        }
    }
}
