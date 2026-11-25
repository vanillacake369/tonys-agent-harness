package core

import "testing"

func TestApplicationFacade(t *testing.T) {
	application := NewApplication()
	if application != (Application{}) {
		t.Fatal("application facade must not hold mutable state")
	}
}
