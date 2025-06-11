class OrderBy {
  final String field;
  final bool isAscending;

  const OrderBy(this.field, this.isAscending);

  @override
  bool operator ==(Object other) {
    return other is OrderBy &&
        other.field == field &&
        other.isAscending == isAscending;
  }

  @override
  int get hashCode => field.hashCode ^ isAscending.hashCode;
}
