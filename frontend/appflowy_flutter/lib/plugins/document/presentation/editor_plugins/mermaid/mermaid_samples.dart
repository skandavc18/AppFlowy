import 'package:flutter/material.dart';

/// A starting point offered when a Mermaid block is still empty.
///
/// Naming the diagram types with a working example is what makes the block
/// approachable — the syntax is the only hard part of Mermaid.
class MermaidSample {
  const MermaidSample({
    required this.label,
    required this.icon,
    required this.source,
  });

  final String label;
  final IconData icon;
  final String source;
}

const kMermaidSamples = <MermaidSample>[
  MermaidSample(
    label: 'Flowchart',
    icon: Icons.account_tree_rounded,
    source: '''
flowchart TD
    A[Start] --> B{Ready?}
    B -->|Yes| C[Process]
    B -->|No| D[Wait]
    D --> B
    C --> E[Done]''',
  ),
  MermaidSample(
    label: 'Sequence',
    icon: Icons.swap_horiz_rounded,
    source: '''
sequenceDiagram
    participant User
    participant App
    participant Server
    User->>App: Request
    App->>Server: API call
    Server-->>App: Response
    App-->>User: Result''',
  ),
  MermaidSample(
    label: 'Class',
    icon: Icons.schema_rounded,
    source: '''
classDiagram
    class Animal {
      +String name
      +int age
      +speak()
    }
    class Dog {
      +fetch()
    }
    Animal <|-- Dog''',
  ),
  MermaidSample(
    label: 'State',
    icon: Icons.route_rounded,
    source: '''
stateDiagram-v2
    [*] --> Idle
    Idle --> Running : start
    Running --> Idle : stop
    Running --> [*] : finish''',
  ),
  MermaidSample(
    label: 'Entities',
    icon: Icons.table_chart_rounded,
    source: '''
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    CUSTOMER {
      string name
      string email
    }''',
  ),
  MermaidSample(
    label: 'Pie',
    icon: Icons.pie_chart_rounded,
    source: '''
pie title Where the day goes
    "Focus" : 42
    "Meetings" : 26
    "Email" : 18
    "Breaks" : 14''',
  ),
  MermaidSample(
    label: 'Mind map',
    icon: Icons.hub_rounded,
    source: '''
mindmap
  root((Project))
    Research
      Interviews
      Surveys
    Design
      Wireframes
    Build
      Frontend
      Backend''',
  ),
  MermaidSample(
    label: 'Timeline',
    icon: Icons.timeline_rounded,
    source: '''
timeline
    title Product history
    section Early
      2021 : Prototype
      2022 : First release
    section Growth
      2023 : Mobile app
      2024 : Collaboration''',
  ),
  MermaidSample(
    label: 'Gantt',
    icon: Icons.view_timeline_rounded,
    source: '''
gantt
    title Release plan
    dateFormat YYYY-MM-DD
    section Design
      Research      : 2024-01-01, 7d
      Wireframes    : 2024-01-08, 5d
    section Build
      Implementation: 2024-01-15, 14d
      Review        : 2024-01-29, 4d''',
  ),
];
