import {BehaviorSubject, Operator} from 'rxjs'

export class SvelteSubject<T> extends BehaviorSubject<T> {
  set(value: T) {
    super.next(value);
  }

  // lift<R>(operator: Operator<T, R>): SvelteSubject<R> {
  //   const result = new SvelteSubject<R>();
  //   result.operator = operator;
  //   result.source = this;
  //   return result;
  // }
}
