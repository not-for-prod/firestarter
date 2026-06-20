package payment

import (
	"errors"
	"strings"
	"time"

	"github.com/shopspring/decimal"
)

type DepositID string

func (id DepositID) String() string {
	return string(id)
}

func (id DepositID) IsZero() bool {
	return strings.TrimSpace(string(id)) == ""
}

type PaymentID string

func (id PaymentID) String() string {
	return string(id)
}

func (id PaymentID) IsZero() bool {
	return strings.TrimSpace(string(id)) == ""
}

type RequisiteID string

func (id RequisiteID) String() string {
	return string(id)
}

func (id RequisiteID) IsZero() bool {
	return strings.TrimSpace(string(id)) == ""
}

type DepositState string

func (s DepositState) String() string {
	return string(s)
}

const (
	DepositStatePending   DepositState = "pending"
	DepositStateConfirmed DepositState = "confirmed"
	DepositStateCancelled DepositState = "cancelled"
	DepositStateFailed    DepositState = "failed"
)

type EventType string

func (t EventType) String() string {
	return string(t)
}

type DepositEventType string

func (t DepositEventType) String() string {
	return string(t)
}

func (t DepositEventType) EventType() EventType {
	return EventType(t)
}

const (
	DepositEventTypeConfirmed DepositEventType = "confirmed"
	DepositEventTypeCancelled DepositEventType = "cancelled"
	DepositEventTypeFailed    DepositEventType = "failed"
)

type Event interface{}

var (
	ErrDepositIDRequired             = errors.New("deposit id is required")
	ErrPaymentIDRequired             = errors.New("payment id is required")
	ErrRequisiteIDRequired           = errors.New("requisite id is required")
	ErrNegativeAmount                = errors.New("amount must be non-negative")
	ErrNegativeFee                   = errors.New("fee must be non-negative")
	ErrInvalidDepositStateTransition = errors.New("invalid deposit state transition")
	ErrCancelReasonRequired          = errors.New("cancel reason is required")
	ErrFailReasonRequired            = errors.New("fail reason is required")
)

type Deposit struct {
	ID          DepositID
	PaymentID   PaymentID
	RequisiteID RequisiteID
	State       DepositState
	Amount      decimal.Decimal
	Fee         decimal.Decimal

	CancelReason string
	FailReason   string

	CreatedAt   time.Time
	ConfirmedAt *time.Time
	CancelledAt *time.Time
	FailedAt    *time.Time
}

func NewDeposit(
	id DepositID,
	paymentID PaymentID,
	requisiteID RequisiteID,
	amount decimal.Decimal,
	fee decimal.Decimal,
	createdAt time.Time,
) (*Deposit, error) {
	switch {
	case id.IsZero():
		return nil, ErrDepositIDRequired
	case paymentID.IsZero():
		return nil, ErrPaymentIDRequired
	case requisiteID.IsZero():
		return nil, ErrRequisiteIDRequired
	case amount.IsNegative():
		return nil, ErrNegativeAmount
	case fee.IsNegative():
		return nil, ErrNegativeFee
	}

	return &Deposit{
		ID:          id,
		PaymentID:   paymentID,
		RequisiteID: requisiteID,
		State:       DepositStatePending,
		Amount:      amount,
		Fee:         fee,
		CreatedAt:   createdAt.UTC(),
	}, nil
}

func (d *Deposit) Copy() *Deposit {
	if d == nil {
		return nil
	}

	clone := *d
	clone.ConfirmedAt = copyTimePtr(d.ConfirmedAt)
	clone.CancelledAt = copyTimePtr(d.CancelledAt)
	clone.FailedAt = copyTimePtr(d.FailedAt)

	return &clone
}

func (d *Deposit) Confirm(occurredAt time.Time) (*DepositEvent, error) {
	if d.State != DepositStatePending {
		return nil, ErrInvalidDepositStateTransition
	}

	before := d.Copy()
	at := occurredAt.UTC()

	d.State = DepositStateConfirmed
	d.CancelReason = ""
	d.FailReason = ""
	d.ConfirmedAt = &at
	d.CancelledAt = nil
	d.FailedAt = nil

	return newDepositEvent(DepositEventTypeConfirmed, d.ID, before, d.Copy(), at), nil
}

func (d *Deposit) Cancel(reason string, occurredAt time.Time) (*DepositEvent, error) {
	if d.State != DepositStatePending {
		return nil, ErrInvalidDepositStateTransition
	}

	reason = strings.TrimSpace(reason)
	if reason == "" {
		return nil, ErrCancelReasonRequired
	}

	before := d.Copy()
	at := occurredAt.UTC()

	d.State = DepositStateCancelled
	d.CancelReason = reason
	d.FailReason = ""
	d.CancelledAt = &at
	d.ConfirmedAt = nil
	d.FailedAt = nil

	return newDepositEvent(DepositEventTypeCancelled, d.ID, before, d.Copy(), at), nil
}

func (d *Deposit) Fail(reason string, occurredAt time.Time) (*DepositEvent, error) {
	if d.State != DepositStatePending {
		return nil, ErrInvalidDepositStateTransition
	}

	reason = strings.TrimSpace(reason)
	if reason == "" {
		return nil, ErrFailReasonRequired
	}

	before := d.Copy()
	at := occurredAt.UTC()

	d.State = DepositStateFailed
	d.FailReason = reason
	d.CancelReason = ""
	d.FailedAt = &at
	d.ConfirmedAt = nil
	d.CancelledAt = nil

	return newDepositEvent(DepositEventTypeFailed, d.ID, before, d.Copy(), at), nil
}

type DepositEvent struct {
	Type        DepositEventType
	AggregateID DepositID
	Before      *Deposit
	After       *Deposit
	OccurredAt  time.Time
}

func newDepositEvent(
	eventType DepositEventType,
	aggregateID DepositID,
	before *Deposit,
	after *Deposit,
	occurredAt time.Time,
) *DepositEvent {
	return &DepositEvent{
		Type:        eventType,
		AggregateID: aggregateID,
		Before:      before.Copy(),
		After:       after.Copy(),
		OccurredAt:  occurredAt.UTC(),
	}
}

func copyTimePtr(src *time.Time) *time.Time {
	if src == nil {
		return nil
	}

	copied := src.UTC()
	return &copied
}
